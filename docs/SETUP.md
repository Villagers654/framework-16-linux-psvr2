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
./scripts/build-envision-runtime.sh
```

The build script compiles the pinned, already-patched Monado and xrizer trees,
checks every required PSVR2 feature, and rejects unresolved runtime libraries.
The Envision profile has source pulling disabled, so opening Envision cannot
silently replace those sources.

Build and install the patched dashboard:

```bash
./scripts/build-wayvr.sh
./scripts/build-xr-chaperone.sh
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
`psvr2-room-setup`. RiftLift's xrizer component supplies the HMD proximity signal
that standard OpenXR controller bindings cannot express, so a centered 2×2 m default polygon is
created automatically. The setup app writes the active `chaperone_info.vrchap`
play area file that Monado reads at startup; this is the source of the in-headset
play boundaries (not another runtime UI).

The boundary importer copies Sony's saved collision polygon directly because it
is already in OpenXR standing/STAGE coordinates. Monado's SteamVR-driver bridge
applies the saved standing transform to HMD and controller poses, so the warning
wall and tracked devices share one calibrated coordinate system.

Room Setup alone uses RiftLift xrizer's opt-in
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

When the wizard saves a changed play area, the launcher waits for all three
driver state files—`chaperone_info.vrchap`, `sceBoundaryMeta.bin`, and
`sceMapDb.bin`—to change and remain stable for ten seconds before closing Room
Setup and reloading Monado. The set is backed up before calibration; an
interrupted or partial transaction is rejected and the previous complete set
is restored. A successful set is also stored as the authoritative calibration
and restored before every later runtime start, so driver map optimization cannot
accumulate a different standing origin across restarts. The reload is required
because the PSVR2 driver and xrizer both capture the standing/raw transform at
process startup.

## 5. Oculus-style visual boundary overlay

After a valid room is saved, run once:

```bash
psvr2-chaperone configure
```

That writes `~/.config/xr-chaperone/chaperone.toml` and captures your room
polygon for warning visual geometry and fade behavior.

The overlay is started automatically from `psvr2-fossvr-start` and `psvr2-room-setup`
to keep your existing room setup flow unchanged.

Disable it temporarily in `~/.config/psvr2-linux/settings.env` if a title needs
unrestricted space:

```bash
perl -i -pe 's/^PSVR2_CHAPERONE_ENABLE=.*/PSVR2_CHAPERONE_ENABLE=0/' ~/.config/psvr2-linux/settings.env
```

## 6. Optional Meta Rift games

Meta/Revive compatibility is maintained independently by RiftLift. This
repository does not patch Meta, Revive, or Rift game launch behavior. Install
RiftLift's pinned release through the thin third-party helper, sign in once,
then add any owned Rift store URL:

```bash
./scripts/install-riftlift.sh
riftlift login
riftlift add 'https://www.meta.com/experiences/APP_ID/'
```

RiftLift persists the Horizon Link login, verifies entitlement, downloads the
current PC build, and registers a generic Steam VR shortcut. The startup library
scan imports that shortcut into WayVR; no title-specific Framework patch is
required. RiftLift's own README and `riftlift doctor` are authoritative for the
Meta compatibility stack.

## 7. Everyday use

Power on the headset and controllers. The USB monitor starts Monado and WayVR,
which opens directly to installed Steam VR games. Select a cover and Play.

The WayVR game cache and Monado launch metadata are regenerated from Steam
manifest changes whenever you install or remove titles. A session-start scan
also discovers Steam VR-manifest entries, including non-Steam launchers such as
Revive games; headset startup performs the same scan before WayVR opens. A
session-wide Steam environment exports the active Monado runtime and xrizer
bridge ensures newly installed titles use the correct runtime immediately. For
a manual refresh during an existing session, run:

```bash
psvr2-sync-steam-vr-games --discovery-only
```

This can be run while Steam is running and only refreshes the WayVR cache; it
does not change launch options or Steam config files.

`psvr2-sync-steam-vr-games` also handles games whose native Linux depot omits
VR. In particular, **Keep Talking and Nobody Explodes** is pinned to Proton
Experimental so its Windows-only VR mode is selected when launched from the
headset. A normal desktop launch remains in its normal non-VR mode; the WayVR
Games launch uses Steam's VR action automatically.

The common game wrapper disables desktop-vblank pacing for every VR title and
runs each launch in an isolated process group plus a transient systemd scope.
OpenXR remains the only frame clock, and the scope terminates all of a game's
Proton/Wine children if the headset disconnects—even when Revive reparents an
injected process outside the launcher's process group.

- PS button: toggle the WayVR dashboard.
- Press either PS button and pull either trigger within three quarters of a second, in either order: save the current VR spectator view to
  `~/Pictures/VR Screenshots/`.
- Manual start/stop: `psvr2-fossvr-start` / `psvr2-fossvr-stop`.

The shortcut captures Monado's canonical undistorted left-eye spectator view,
so it works independently of whether a game creates an XWayland desktop window.
