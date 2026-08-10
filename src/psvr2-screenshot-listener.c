#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <linux/hidraw.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define SONY_VENDOR_ID 0x054c
#define PSSENSE_LEFT_PRODUCT_ID 0x0e45
#define PSSENSE_RIGHT_PRODUCT_ID 0x0e46
#define MAX_HIDRAW_DEVICES 64
#define CHORD_WINDOW_MS 750
#define CAPTURE_COOLDOWN_MS 1000
#define SAMPLE_INTERVAL_NS 20000000L

struct controller {
    int fd;
    bool initialized;
    bool ps_held;
    bool trigger_held;
    bool announced;
    bool detected;
};

static int64_t
monotonic_ms(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0;
    }
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static bool
is_pssense(int fd)
{
    struct hidraw_devinfo info = {0};
    if (ioctl(fd, HIDIOCGRAWINFO, &info) != 0 || info.vendor != SONY_VENDOR_ID) {
        return false;
    }
    return info.product == PSSENSE_LEFT_PRODUCT_ID || info.product == PSSENSE_RIGHT_PRODUCT_ID;
}

static void
open_controllers(struct controller controllers[MAX_HIDRAW_DEVICES], bool full_scan)
{
    for (int index = 0; index < MAX_HIDRAW_DEVICES; ++index) {
        if (controllers[index].fd >= 0) {
            continue;
        }

        char path[32];
        snprintf(path, sizeof(path), "/dev/hidraw%d", index);
        if (!controllers[index].detected && !full_scan) {
            continue;
        }
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) {
            controllers[index].detected = false;
            continue;
        }
        if (!controllers[index].detected && !is_pssense(fd)) {
            close(fd);
            continue;
        }

        controllers[index].fd = fd;
        controllers[index].detected = true;
        if (!controllers[index].announced) {
            controllers[index].announced = true;
            fprintf(stderr, "Watching %s for the screenshot chord\n", path);
        }
    }
}

static void
launch_screenshot(void)
{
    pid_t child = fork();
    if (child < 0) {
        fprintf(stderr, "Could not fork screenshot helper: %s\n", strerror(errno));
        return;
    }
    if (child == 0) {
        execlp("psvr2-screenshot", "psvr2-screenshot", (char *)NULL);
        fprintf(stderr, "Could not launch psvr2-screenshot: %s\n", strerror(errno));
        _exit(127);
    }
}

static void
consume_report(struct controller *controller,
               const uint8_t *report,
               ssize_t length,
               int64_t *ps_pressed_at,
               int64_t *trigger_pressed_at,
               int64_t *cooldown_until)
{
    size_t common_offset;
    if (length >= 12 && report[0] == 0x31) {
        common_offset = 2; /* Bluetooth report header. */
    } else if (length >= 11 && report[0] == 0x01) {
        common_offset = 1; /* USB report header. */
    } else {
        return;
    }

    /* Layout from Monado's community PS Sense driver (pssense_protocol.h). */
    bool ps_held = (report[common_offset + 8] & 0x10) != 0;
    bool trigger_held = report[common_offset + 2] > 127;
    if (!controller->initialized) {
        controller->initialized = true;
        controller->ps_held = ps_held;
        controller->trigger_held = trigger_held;
        return;
    }

    int64_t now = monotonic_ms();
    if (ps_held && !controller->ps_held) {
        *ps_pressed_at = now;
    }
    if (trigger_held && !controller->trigger_held) {
        *trigger_pressed_at = now;
    }
    controller->ps_held = ps_held;
    controller->trigger_held = trigger_held;

    if (*ps_pressed_at > 0 && now - *ps_pressed_at > CHORD_WINDOW_MS) {
        *ps_pressed_at = 0;
    }
    if (*trigger_pressed_at > 0 && now - *trigger_pressed_at > CHORD_WINDOW_MS) {
        *trigger_pressed_at = 0;
    }
    if (now < *cooldown_until || *ps_pressed_at == 0 || *trigger_pressed_at == 0) {
        return;
    }

    int64_t difference = *ps_pressed_at - *trigger_pressed_at;
    if (difference < 0) {
        difference = -difference;
    }
    if (difference <= CHORD_WINDOW_MS) {
        fprintf(stderr, "PSVR2 screenshot chord pressed\n");
        launch_screenshot();
        *ps_pressed_at = 0;
        *trigger_pressed_at = 0;
        *cooldown_until = now + CAPTURE_COOLDOWN_MS;
    }
}

int
main(void)
{
    struct controller controllers[MAX_HIDRAW_DEVICES];
    struct pollfd poll_fds[MAX_HIDRAW_DEVICES];
    for (int index = 0; index < MAX_HIDRAW_DEVICES; ++index) {
        controllers[index] = (struct controller){.fd = -1};
    }

    signal(SIGCHLD, SIG_IGN);
    int64_t ps_pressed_at = 0;
    int64_t trigger_pressed_at = 0;
    int64_t cooldown_until = 0;
    int64_t next_full_scan = 0;

    for (;;) {
        int64_t now = monotonic_ms();
        bool full_scan = now >= next_full_scan;
        if (full_scan) {
            next_full_scan = now + 1000;
        }
        open_controllers(controllers, full_scan);
        int poll_count = 0;
        int controller_indices[MAX_HIDRAW_DEVICES];
        for (int index = 0; index < MAX_HIDRAW_DEVICES; ++index) {
            if (controllers[index].fd < 0) {
                continue;
            }
            poll_fds[poll_count] = (struct pollfd){
                .fd = controllers[index].fd,
                .events = POLLIN,
            };
            controller_indices[poll_count++] = index;
        }

        int ready = poll(poll_fds, (nfds_t)poll_count, 1000);
        if (ready < 0 && errno != EINTR) {
            fprintf(stderr, "Controller poll failed: %s\n", strerror(errno));
            return 1;
        }
        for (int poll_index = 0; poll_index < poll_count; ++poll_index) {
            int index = controller_indices[poll_index];
            if ((poll_fds[poll_index].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
                close(controllers[index].fd);
                controllers[index] = (struct controller){.fd = -1};
                continue;
            }
            if ((poll_fds[poll_index].revents & POLLIN) == 0) {
                continue;
            }

            uint8_t report[128];
            ssize_t length = read(controllers[index].fd, report, sizeof(report));
            if (length > 0) {
                consume_report(&controllers[index], report, length, &ps_pressed_at,
                               &trigger_pressed_at, &cooldown_until);
            }
        }

        /* Reopening discards high-rate motion reports queued between samples. */
        for (int index = 0; index < MAX_HIDRAW_DEVICES; ++index) {
            if (controllers[index].fd >= 0) {
                close(controllers[index].fd);
                controllers[index].fd = -1;
            }
        }
        struct timespec sample_interval = {.tv_nsec = SAMPLE_INTERVAL_NS};
        nanosleep(&sample_interval, NULL);
    }
}
