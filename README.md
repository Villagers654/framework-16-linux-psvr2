# Framework 16 Linux PSVR2

An opinionated, reproducible PSVR2 PCVR setup for Linux, developed and tested
on a Framework Laptop 16 with the Radeon RX 7700S Expansion Bay GPU, Bazzite,
GNOME Wayland, and Sony's PSVR2 PC adapter.

The finished experience is deliberately console-like:

1. Turn on the Sense controllers and headset in either order.
2. Monado and WayVR start automatically.
3. The headset opens directly to a filtered grid of installed Steam VR games.
4. **PSVR2 Room Setup** is in that grid beside the games.
5. Point, pull the trigger, and play.
6. A borderless fullscreen spectator view appears on the laptop display.

The tested default is **120 Hz** at Monado's **170% compositor scale**, which
reports a distortion-corrected recommendation of **3400×3468 per eye** on this
PSVR2. Per-game Steam resolution overrides remain available.

> [!CAUTION]
> This is a community Linux stack built around experimental software. It is
> not supported by Sony, Valve, Framework, or the upstream projects. Read the
> hardware labels below before applying kernel or GPU settings.

## What is portable and what is machine-specific?

| Component | Scope | Why |
|---|---|---|
| PSVR2 Toolkit + Ignition | **Linux PSVR2** | Runs Sony's SteamVR driver through Proton and exposes it to Linux VR runtimes. |
| Supremium Monado + xrizer | **Linux PSVR2** | Supplies OpenXR and translates OpenVR games without relying on SteamVR's compositor. |
| WayVR launcher patches | **Linux PSVR2** | Opens a VR-only game grid, launches explicit VR modes, and binds native Sense controls. |
| `bluetooth.disable_ertm=1` | **Linux / controller-specific** | Compatibility workaround for Sense Bluetooth pairing; try without it first on current kernels. |
| `amdgpu.dcdebugmask=0xc10` | **AMD-specific, experimental** | The exact setting used on the tested machine to stabilize direct-display/DRM behavior. Do not apply on Intel/NVIDIA. |
| AMD VR power profile service | **AMD-specific** | Prevents between-frame dGPU downclocking and runtime suspend while PSVR2 is connected. |
| RX 7700S Vulkan ID `1002:7480` | **Framework 16 RX 7700S-specific** | Forces rendering onto the GPU physically wired to the rear Expansion Bay DisplayPort. |
| PCI address `0000:03:00.0` | **This tested Framework 16 only** | PCI addresses can differ. The installer detects yours; never copy this value blindly. |
| `/usr/bin/bazzite-steam` and `rpm-ostree kargs` | **Bazzite-specific** | Other distributions should use their native Steam package and bootloader tooling. |
| GNOME Wayland | **Tested desktop** | The Monado path avoids SteamVR's unreliable GNOME DRM-lease path. WayVR uses PipeWire for the desktop. |

## Hardware assumptions

- Framework Laptop 16 (AMD 7040 generation tested)
- Radeon RX 7700S Expansion Bay GPU
- Sony PlayStation VR2 PC adapter with its power supply
- DisplayPort connected to the **rear dGPU output**, not a side Expansion Card
- USB from the Sony adapter connected to any functioning Framework USB-A path
- PSVR2 Sense controllers paired over Bluetooth

Framework's side Expansion Card display outputs are normally routed through the
iGPU. The rear USB-C/DisplayPort output on the RX 7700S Expansion Bay is the
important part of this configuration.

## Prerequisites and dependencies

This repository contains integration scripts and source patches, not the
commercial software or prebuilt community runtime. Install these prerequisites
before running the quick start.

| Requirement | What is needed | Notes |
|---|---|---|
| Steam stack | Native Linux Steam, SteamVR, PlayStation VR2 App, and Proton Experimental | The scripts default to `~/.local/share/Steam`. Flatpak Steam is not currently supported without changing paths and sandbox permissions. Start Steam and sign in at least once. |
| VR builder | Envision and an OpenXR loader/development package | Envision builds the pinned Monado and xrizer sources. On Fedora/Bazzite the development package is `openxr-devel`. |
| Graphics | A working Vulkan driver and `vulkaninfo` | Use Mesa RADV on AMD. Do not use AMDVLK or AMDGPU-PRO for this wired-VR path. |
| Host services | systemd user services, udev, BlueZ, PipeWire, and WirePlumber | Required for automatic startup, device permissions, Sense pairing, and PSVR2 audio routing. |
| Script utilities | Bash, Git, cURL, UnZip, `jq`, Python 3, `usbutils`, `pciutils`, and `iproute` | These supply `git`, `curl`, `unzip`, `jq`, `python3`, `lsusb`, `lspci`, and `ss`. Internet access to GitHub, GitLab, Steam, and Homebrew is required during setup. |
| WayVR build | Rust/Cargo, CMake, Ninja, Meson, pkg-config, shaderc, ALSA, PipeWire, xkbcommon, D-Bus, and OpenSSL development files | The tested Bazzite setup supplies this self-contained toolchain through Homebrew; equivalent distribution development packages also work. |
| Screenshot shortcut | `wmctrl`, ImageMagick, and `notify-send` | Optional. Only required for the PS-button + trigger screenshot chord. |

The headset and Sony PC adapter must have PC-compatible firmware. If the
PlayStation VR2 App cannot perform a required firmware update under Proton,
update them once from Windows before continuing. A BlueZ-compatible Bluetooth
adapter is required only when you reach Sense controller pairing.

The tested Bazzite host layers the packages that must integrate with the host:

```bash
rpm-ostree install envision openxr-devel wmctrl ImageMagick
```

Bazzite already includes most runtime utilities listed above. Confirm that
`git curl unzip jq python3 lsusb lspci ss bluetoothctl wpctl vulkaninfo` are
available. Their Fedora package names are `git-core`, `curl`, `unzip`, `jq`,
`python3`, `usbutils`, `pciutils`, `iproute`, `bluez`, `wireplumber`, and
`vulkan-tools`; `libnotify` supplies the optional `notify-send` command.

Install Homebrew for Linux, then install the complete tested WayVR build
toolchain:

```bash
brew install cmake ninja meson rust shaderc pkgconf \
  alsa-lib pipewire libxkbcommon dbus openssl@3
```

On mutable Fedora, Arch, Debian/Ubuntu, or another distribution, install the
equivalent runtime and `-devel`/`-dev` packages through the native package
manager. Package names differ, but every non-optional capability in the table
is required.
Allow several gigabytes for SteamVR, Proton prefixes, Monado/xrizer sources,
and release builds.

## Quick start

Install the prerequisites above first. On Bazzite, also read
[docs/BAZZITE.md](docs/BAZZITE.md) before changing kernel arguments.

```bash
git clone https://github.com/Villagers654/framework-16-linux-psvr2.git
cd framework-16-linux-psvr2
./install.sh --user --framework16-rx7700s
./scripts/fetch-community-tools.sh
./scripts/install-room-setup-binding.sh
./scripts/prepare-envision-runtime.sh
./scripts/build-wayvr.sh
sudo ./install.sh --system --framework16-rx7700s
```

Then:

1. Open Envision.
2. Select **PSVR2 Toolkit – 120 Hz / 1.7x**.
3. Choose **Clean Build** once.
4. Run `./scripts/verify.sh`.
5. Run `./scripts/verify-haptics.sh` for a controller-feedback validation pass.
6. Reboot if you installed optional kernel arguments.

The installer never overwrites an existing settings file. Review it here:

```bash
$EDITOR ~/.config/psvr2-linux/settings.env
```

For the exact from-scratch sequence, including Steam app preparation and
controller pairing, read [docs/SETUP.md](docs/SETUP.md).

## Everyday use

- Power on/connect PSVR2: the runtime and game launcher start automatically.
- The laptop shows a borderless fullscreen, GPU-native left-eye spectator view
  while the headset continues rendering at 120 Hz. Set
  `PSVR2_SPECTATOR_ENABLE=0` to disable it in `settings.env`.
- Run `psvr2-spectator on`, `psvr2-spectator off`, or
  `psvr2-spectator toggle` to change that choice persistently. The command
  cleanly restarts an active VR session; add `--no-restart` to defer it. GNOME's
  app grid also contains **Toggle PSVR2 Spectator View**.
- Turn controllers on afterward: the monitor detects them and refreshes Monado.
- Press either PS button: show or hide the WayVR dashboard.
- Press either PS button, then pull either trigger within half a second: save the VR mirror to
  `~/Pictures/VR Screenshots/`.
- Select **Games**: only detected Steam VR titles are listed.
- Select **PSVR2 Room Setup**: run full room-scale calibration from the headset.
- Select **Applications**: launch desktop applications or view the GNOME desktop.
- Exit a game or Room Setup: the wrapper restores WayVR directly to the Games
  dashboard while keeping Monado and the calibrated tracking origin alive.
- Disconnect the headset's USB, DisplayPort, adapter power, or headset cable:
  the active VR title, WayVR, Monado, and Ignition helper close automatically,
  and the previous desktop audio output is restored. Steam itself stays open.
- Stop VR: launch **Stop PSVR2 (Monado)** from GNOME or run `psvr2-fossvr-stop`.
- Manual start: launch **PSVR2 (Monado + WayVR)** or run `psvr2-fossvr-start`.

If you manually stop VR while the headset remains connected, the connection monitor
does not immediately fight you and restart it. Power-cycle the headset or use
the manual launcher when you want VR again.

## Repository layout

- `bin/` – portable versions of every helper used by the working setup
- `systemd/user/` – Monado, WayVR, maintenance, and connection-monitor user units
- `systemd/system/` – optional AMD dGPU power guard
- `udev/` – PSVR2 permissions and conditional AMD power hooks
- `patches/` – exact Monado, xrizer, and WayVR source changes
- `config/` – settings and Envision/WayVR configuration templates
- `desktop/` – GNOME application launchers
- `scripts/` – downloads, source preparation, build, and verification
- `docs/` – full setup, architecture, platform-specific notes, and troubleshooting

## Pinned, tested versions

| Project | Version/commit |
|---|---|
| PSVR2 Toolkit | `v1.0.0-experimental-1` (`PSVR2TK-win64-Ignition.zip`) |
| Ignition | `v1.0.0` |
| PSVR2Toolkit.UnitySetup | `v1.1.0` |
| SteamVRLinuxFixes | `v0.1.4` |
| Supremium Monado branch | `psvr2-linux-steam-lh` at `8bd01e7edec8028f65c7bff925195f0454d4bc9f` |
| xrizer | `6c3e45f4c18b014a7aba87282ee0677306315052` |
| WayVR | `d93b74cc8aa01ea17d72d46ce016e47286409f92` (26.7.1) |

See [docs/UPSTREAM.md](docs/UPSTREAM.md) for links, licenses, and what each
project contributes.

## Security and redistribution

This repository intentionally does **not** contain:

- Sony or Steam binaries
- Bnuuy release binaries
- a Wine/Proton prefix
- Steam account data or application manifests
- Bluetooth MAC addresses
- eye, room, or lens calibration data

The download script fetches public release assets from their upstream project
pages. Source patches are provided so the custom binaries can be rebuilt.
