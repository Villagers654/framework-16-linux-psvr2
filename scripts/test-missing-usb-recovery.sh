#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
cleanup() {
    [[ -z "${enumerator_pid:-}" ]] || kill "$enumerator_pid" 2>/dev/null || true
    [[ -z "${monitor_pid:-}" ]] || kill "$monitor_pid" 2>/dev/null || true
    rm -rf -- "$test_root"
}
trap cleanup EXIT

usb_root="$test_root/usb"
device_root="$test_root/devices"
drm_root="$test_root/drm"
hub="$device_root/0000:00:00.0/usb2/2-2"
mkdir -p "$usb_root" "$hub" "$drm_root/card1-DP-1"
printf '0x1022\n' > "$device_root/0000:00:00.0/vendor"
printf '0x0c0330\n' > "$device_root/0000:00:00.0/class"
printf '05e3\n' > "$hub/idVendor"
printf '0625\n' > "$hub/idProduct"
printf '1\n' > "$hub/authorized"
ln -s "$hub" "$usb_root/2-2"
printf 'connected\n' > "$drm_root/card1-DP-1/status"
printf 'PS VR2\n' > "$drm_root/card1-DP-1/edid"

(
    sleep 2.2
    mkdir -p "$usb_root/2-2.2"
    printf '054c\n' > "$usb_root/2-2.2/idVendor"
    printf '0cde\n' > "$usb_root/2-2.2/idProduct"
) &
enumerator_pid=$!

PSVR2_USB_ROOT="$usb_root" \
PSVR2_USB_DEVICE_ROOT="$device_root" \
PSVR2_DRM_ROOT="$drm_root" \
    "$repo/systemd/system/psvr2-usb-recover" > "$test_root/recover.log"
wait "$enumerator_pid"
enumerator_pid=
grep -Fq 'Recovered the missing PSVR2 USB function' "$test_root/recover.log"
grep -Fxq '1' "$hub/authorized"

helpers="$test_root/helpers"
fake_bin="$test_root/bin"
mkdir -p "$helpers" "$fake_bin"
for helper in psvr2-fossvr-start psvr2-fossvr-stop; do
    printf '#!/usr/bin/bash\nexit 0\n' > "$helpers/$helper"
    chmod 0755 "$helpers/$helper"
done
cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "$PSVR2_TEST_SYSTEMCTL_LOG"
exit 0
EOF
chmod 0755 "$fake_bin/systemctl"
printf 'inactive\n' > "$test_root/runtime-state"
unlink "$usb_root/2-2.2/idVendor"
unlink "$usb_root/2-2.2/idProduct"
rmdir "$usb_root/2-2.2"

PATH="$fake_bin:$PATH" \
PSVR2_TEST_MODE=1 \
PSVR2_TEST_RUNTIME_STATE_FILE="$test_root/runtime-state" \
PSVR2_TEST_SYSTEMCTL_LOG="$test_root/systemctl.log" \
PSVR2_USB_ROOT="$usb_root" \
PSVR2_DRM_ROOT="$drm_root" \
PSVR2_HELPER_DIR="$helpers" \
PSVR2_COMMON_PATH="$repo/lib/psvr2-common.sh" \
PSVR2_CONFIG="$test_root/missing-settings.env" \
PSVR2_MISSING_USB_RECOVERY_SECONDS=1 \
    "$repo/bin/psvr2-autostart-monitor" > "$test_root/monitor.log" 2>&1 &
monitor_pid=$!
sleep 3
kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true
monitor_pid=
grep -Fq -- '--no-ask-password --no-block start psvr2-usb-recover.service' \
    "$test_root/systemctl.log"

echo 'PSVR2 missing-USB guarded recovery test passed.'
