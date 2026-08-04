# Complete setup

This is the reproducible version of the tested Framework 16/Bazzite setup.
Commands marked optional are not required on every Linux system.

## 1. Hardware and Steam

1. Connect the Sony PC adapter's DisplayPort to the **rear RX 7700S Expansion
   Bay output**. A Framework side DisplayPort Expansion Card is normally on the
   iGPU and is not equivalent.
2. Connect adapter power and USB. Framework USB-A Expansion Cards appear behind
   internal USB hubs; that is normal and is not a reason to reject the port.
3. Install Steam, SteamVR, PlayStation VR2 App, and Proton Experimental. Run the
   Sony app once on Windows only if a headset/adapter firmware update is needed.
4. Install Envision, Git, Rust, CMake/Ninja, `jq`, `curl`, `unzip`, BlueZ,
   OpenXR loader/development files, Vulkan tools, `wmctrl`, and ImageMagick.

## 2. Install this integration

```bash
git clone https://github.com/Villagers654/framework-16-linux-psvr2.git
cd framework-16-linux-psvr2
./install.sh --user --framework16-rx7700s
./scripts/fetch-community-tools.sh
./scripts/install-room-setup-binding.sh
./scripts/prepare-envision-runtime.sh
```

Open Envision, select **PSVR2 Toolkit - 120 Hz / 1.7x**, and run **Clean
Build** once. The installed profile has source pulling disabled, so Envision
builds the pinned, already-patched Monado and xrizer trees without replacing
them.

Build and install the patched dashboard:

```bash
./scripts/build-wayvr.sh
sudo ./install.sh --system --framework16-rx7700s
./scripts/verify.sh
```

On Bazzite, see [BAZZITE.md](BAZZITE.md) before installing system packages or
kernel arguments.

## 3. Pair Sense controllers

Pair in GNOME Settings → Bluetooth:

- Left controller: hold **PS + Create** until its light flashes blue.
- Right controller: hold **PS + Options** until its light flashes blue.
- Select each “PlayStation VR2 Sense Controller” entry.

The optional MAC fields in `~/.config/psvr2-linux/settings.env` are only for
repairing BlueZ's rare connected-without-HID state. Do not publish those values.

## 4. Room-scale setup

Choose **PSVR2 Room Setup** in WayVR's Games grid or launch
`psvr2-room-setup`. The compatibility layer supplies the HMD proximity signal
that xrizer cannot currently express, so a centered 2×2 m default polygon is
created automatically. Room Setup alone uses xrizer's patched
`RawAndUncalibrated` space, which removes the saved chaperone transform from
the HMD pose so the Toolkit's raw passthrough-camera pose stays aligned. Games
and WayVR continue to use the calibrated STAGE space.

- Trigger: expand when starting inside; erase when starting outside.
- Grip: set floor in the floor step; grab/move a boundary point in draw mode.
- X/A: snap to a boundary point.
- Y/B: delete the selected point.
- Thumbstick: move floor; thumbstick click moves the whole play area.

Finish the wizard to write the full room-scale boundary. This project does not
substitute standing-only calibration.

## 5. Everyday use

Power on the headset and controllers. The USB monitor starts Monado and WayVR,
which opens directly to installed Steam VR games. Select a cover and Play.

- PS button: toggle the WayVR dashboard.
- Hold either PS button, then pull either trigger: save the current XWayland VR mirror to
  `~/Pictures/VR Screenshots/`.
- Manual start/stop: `psvr2-fossvr-start` / `psvr2-fossvr-stop`.

Most Proton VR games expose an XWayland mirror and support the screenshot
shortcut. A native Wayland game with no XWayland mirror must use its own
screenshot function.
