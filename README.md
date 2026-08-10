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
6. The PSVR2 Room Setup boundary is imported into the visual warning overlay.

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
| xr-chaperone | **Linux OpenXR** | Provides Oculus-style visual boundary warnings from your PSVR2 play area in a separate overlay process. |
| [RiftLift](https://github.com/Villagers654/RiftLift) | **Optional Meta Rift games** | Installs and launches owned Rift titles through maintained ReviveXR and Monado integration. |
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
| xr-chaperone | Rust/Cargo plus the WayVR build toolchain | Built from a pinned source commit; no mutable nightly binary is executed. |
| Screenshot shortcut | `wmctrl`, ImageMagick, `flock`, and `notify-send` | Optional. Only required for the PS-button + trigger screenshot chord. |

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
brew install cmake ninja meson rust eigen glslang shaderc pkgconf \
  alsa-lib dav1d hidapi jpeg-turbo libusb pipewire sdl2-compat systemd \
  libxkbcommon dbus openssl@3 \
  vulkan-headers vulkan-loader
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
./scripts/install-community-driver.sh
./scripts/install-room-setup-binding.sh
./scripts/prepare-envision-runtime.sh
./scripts/build-envision-runtime.sh
./scripts/build-wayvr.sh
./scripts/build-xr-chaperone.sh
sudo ./install.sh --system --framework16-rx7700s
```

Then:

1. Open Envision and confirm **PSVR2 Toolkit – 120 Hz / 1.7x** is selected.
2. Run `./scripts/verify.sh`.
3. Run `./scripts/verify-haptics.sh` for a controller-feedback validation pass.
4. Reboot if you installed optional kernel arguments.
5. Run **PSVR2 Room Setup** once; its saved boundary is reused by xr-chaperone.

The installer never overwrites an existing settings file. Review it here:

```bash
$EDITOR ~/.config/psvr2-linux/settings.env
```

For the exact from-scratch sequence, including Steam app preparation and
controller pairing, read [docs/SETUP.md](docs/SETUP.md).

## Clean reset

The installer owns an explicit removal path, including stale files from older
repository versions:

```bash
./install.sh --uninstall-user --purge-data
sudo ./install.sh --uninstall-system
```

This removes the integration, generated source/build trees, prefixes, caches,
configuration, udev rules, and the Framework dGPU service. It deliberately does
not remove Steam, SteamVR, Proton, the PlayStation VR2 App, or any games; manage
those application depots through Steam when a full application redownload is
required.

## Everyday use

- Power on/connect PSVR2: the runtime and game launcher start automatically.
- If the headset enumerates but its USB endpoints fail during driver wake-up,
  the monitor performs one device-scoped USB port reset and retries without
  requiring root, unplugging the adapter, or resetting the surrounding hub.
- A fullscreen, undistorted full-left-eye spectator view opens on the laptop display
  by default and closes with the runtime. Set `PSVR2_SPECTATOR_ENABLE=0` in
  `settings.env` for headset-only output.
- Turn controllers on before or after headset launch: WayVR starts without
  blocking. Controllers can appear live over Bluetooth + HID; no Monado restart
  is required just to expose roles.
- Startup waits for the saved room map and stable positional tracking before
  opening WayVR or Chaperone, so a fake-position 3DoF fallback is never reported
  as ready. It continuously guards that origin after startup and recreates
  clients after relocalization instead of leaving them attached to stale STAGE
  coordinates.
- Run **PSVR2 Room Setup** once; its polygon automatically supplies
  xr-chaperone's warning walls and fade geometry.
- Warning geometry is visual-only and does not hard-block movement.
- Set `PSVR2_CHAPERONE_ENABLE=0` in `settings.env` to disable the overlay.
- Press either PS button: show or hide the WayVR dashboard.
- Press either PS button and pull either trigger within three quarters of a second, in either order: save the VR mirror to
  `~/Pictures/VR Screenshots/`.
- Select **Games**: only detected Steam VR titles are listed.
- Select **PSVR2 Room Setup**: run full room-scale calibration from the headset.
  This atomically validates the boundary, boundary metadata, and spatial map;
  an interrupted or incomplete save restores the previous complete set. The
  successful set becomes the authoritative calibration restored on every
  future runtime start.
- Select **Applications**: launch desktop applications or view the GNOME desktop.
- WayVR remains an active OpenXR overlay during every wrapped game, so its
  watch, notifications, controller shortcuts, and PS-button dashboard remain
  available in native OpenXR, XRizer/OpenVR, and RiftLift/Revive titles.
- A successful launch dismisses the dashboard automatically; either PS button
  opens it again without leaving the game.
- Exit a game or Room Setup: WayVR returns directly to the Games dashboard
  while Monado and the calibrated tracking origin stay alive.
- Disconnect the headset's USB, DisplayPort, adapter power, or headset cable:
  the active VR title, WayVR, Monado, and Ignition helper close automatically,
  and the previous desktop audio output is restored. Steam itself stays open.  
  Controllers stay paired on Bluetooth (unless you set `PSVR2_DISCONNECT_CONTROLLERS=1`
  in `settings.env`), so reusing them after headset reconnection is immediate.
- Stop VR: launch **Stop PSVR2 (Monado)** from GNOME or run `psvr2-fossvr-stop`.
- Manual start: launch **PSVR2 (Monado + WayVR)** or run `psvr2-fossvr-start`.

If you manually stop VR while the headset remains connected, the connection monitor
does not immediately fight you and restart it. Power-cycle the headset or use
the manual launcher when you want VR again.

## Repository layout

- `bin/` – portable versions of every helper used by the working setup
- `systemd/user/` – Monado, WayVR, Steam-library sync, and connection-monitor units
- `systemd/system/` – optional AMD dGPU power guard
- `udev/` – PSVR2 permissions and conditional AMD power hooks
- `patches/` – exact PSVR2-specific Monado and WayVR source changes
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
| Supremium Monado branch | `psvr2-linux-steam-lh` at `8bd01e7edec8028f65c7bff925195f0454d4bc9f` |
| [RiftLift xrizer](https://github.com/Villagers654/xrizer) | `7b5f7e5b6d3c134f951a5547f0466880e7458477` |
| WayVR | `d93b74cc8aa01ea17d72d46ce016e47286409f92` (26.7.1) |
| xr-chaperone | `a0351bd00f208e9f7c7917d413de2accbf9208eb` |

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

The download script accepts only HTTPS and verifies pinned SHA-256 digests before
extracting release assets. Monado, xrizer, WayVR, and xr-chaperone are checked
out by immutable commit and built locally.
