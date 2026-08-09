# Troubleshooting

## Black headset, WayVR absent, or controllers missing

```bash
psvr2-fossvr-stop
psvr2-fossvr-start
systemctl --user status psvr2-fossvr.service psvr2-fossvr-wayvr.service
journalctl --user -u psvr2-fossvr.service -n 150 --no-pager
```

Confirm both controller HID devices exist:

```bash
grep -HlE 'HID_ID=0005:0000054C:00000E4(5|6)' \
  /sys/class/hidraw/hidraw*/device/uevent
```

If BlueZ says connected but neither HID device exists, disconnect and reconnect
the controllers in GNOME Bluetooth settings, then restart WayVR.

If Monado logs still show:

```
Got devices:
  left: <none> (<none>)
  right: <none> (<none>)
```

even when both Sense controllers are paired and visible in Bluetooth, set
`PSVR2_LOAD_PSVR2_SENSE=1` (and restart Monado), then verify that Monado logs
emit `Init playstation_vr2_sense module...` and `TrackedDeviceAdded` lines.

## Blue Monado environment after leaving a game or reconnecting

The blue space is Monado's fallback environment, not a tracking failure. It
means the compositor is healthy but no application or WayVR dashboard is
currently presenting. Current installs run games through `psvr2-fossvr-run`,
which restarts only the WayVR overlay when the game exits and returns directly
to its Games tab. Re-run `./install.sh --user --framework16-rx7700s` to update
an older wrapper. To recover an already-stale session without losing room
calibration, run:

```bash
systemctl --user restart psvr2-fossvr-wayvr.service
```

## Headset enters a boot/restart loop

The autostart monitor now protects against short USB/DP flaps and repeated
hard-runtime failures by requiring sustained link-state transitions before it
stops/starts services and by enforcing a cooldown window after repeated failures.
Hard runtime failures are also counted persistently at
`$XDG_RUNTIME_DIR/psvr2-startup-failure-state` so each automatic restart uses
the same recovery backoff instead of immediately re-entering a tight start loop.

If startup still loops and logs:

- `No builder selected in config (or wasn't compiled in)`  
- `Selected psvr2 because it was certain it could create a head` followed by
  `XRT_ERROR_DEVICE_CREATION_FAILED`

that means the installed Monado binary was built without PlayStation VR2 support
enabled. Rebuild with `XRT_BUILD_DRIVER_PSVR2=ON` and restart:

```bash
./scripts/prepare-envision-runtime.sh
cd ~/.local/share/envision/psvr2-toolkit-monado/xrservice
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado \
  -DXRT_BUILD_DRIVER_PSVR2=ON -DXRT_BUILD_DRIVER_STEAMVR_LIGHTHOUSE=ON -DXRT_BUILD_DRIVER_PSSENSE=ON
cmake --build build -j4 && cmake --install build
systemctl --user restart psvr2-autostart-monitor.service
```

- `PSVR2_LINK_DISCONNECT_CHECKS` (default `2`) controls how many consecutive
  negative link samples are required before a disconnect is considered real.
- `PSVR2_RUNTIME_RETRY_COOLDOWN_SECONDS` (default `90`) pauses startup after
  repeated hard failures.

If the headset remains unstable after a cable/DP reconnect, clear stale state and
reseed the loop with a clean retry:

```bash
psvr2-fossvr-stop
rm -f "$XDG_RUNTIME_DIR/psvr2-startup-cooldown"
psvr2-fossvr-start
```

If you have to clear persisted state for immediate diagnostics (for example, after
testing a firmware or game change), remove both anti-loop files and restart the
monitor:

```bash
rm -f "$XDG_RUNTIME_DIR/psvr2-startup-cooldown" "$XDG_RUNTIME_DIR/psvr2-startup-failure-state"
systemctl --user restart psvr2-autostart-monitor.service
```

If a restart loop still appears, capture the last 200 monitor and Monado lines:

```bash
journalctl --user -u psvr2-autostart-monitor.service -n 300 --no-pager
journalctl --user -u psvr2-fossvr.service -n 300 --no-pager
```

## Automated plug/unplug regression test (non-invasive)

Before deploying startup changes, run the repo-local reconnect test to prove the
monitor handles repeated transitions without entering a retry loop:

```bash
./scripts/verify-reconnect-cycle.sh 5
```

The script runs a synthetic, deterministic 5-cycle headset connect/disconnect
scenario with stubbed helper calls and validates startup/stop counts on each
edge. It is fully local and does not require the headset to be attached.

## VR processes remain after physically disconnecting PSVR2

The lifecycle monitor requires both the Sony USB device and a connected DRM
output whose EDID identifies `PS VR2`. Losing either link stops the wrapped VR
title, WayVR, Monado/Ignition, and the VR audio override. Check the live probe:

```bash
psvr2-autostart-monitor --probe
systemctl --user status psvr2-autostart-monitor.service
```

The probe prints `connected` only when both USB and DisplayPort are present.
Re-run `./install.sh --user --framework16-rx7700s` if an older USB-only monitor
is installed.

## Headset goes black when a game is selected and Steam never starts it

WayVR must send game URLs directly to Steam's native client, not through the
desktop `steam:` URL handler. The latter may be registered to the SteamVR
bridge and will stop the active Monado session during launch. Re-run
`./install.sh`; the patched WayVR and `psvr2-wayvr` wrapper set the direct
client route permanently. A successful launch keeps both
`psvr2-fossvr.service` and `psvr2-fossvr-wayvr.service` active while the game
connects to Monado.

## Room Setup tracks controllers but has no boundary

This is not a standing-only calibration problem. It means the app's optional
`HeadsetOnHead` action never became true. Reapply both fixes and relaunch:

```bash
./scripts/install-room-setup-binding.sh
./scripts/prepare-envision-runtime.sh
```

The binding supplies Sense actions; the scoped xrizer patch supplies proximity
only when `psvr2-room-setup` sets `XRIZER_FORCE_HEADSET_ON_HEAD=1`.

## Boundary warning overlay is missing or not showing in games

Run the overlay setup wizard once so xr-chaperone has a polygon to render:

```bash
psvr2-chaperone configure
```

This writes `~/.config/xr-chaperone/chaperone.toml`. The boundary visual is a
warning cue only in this repo's Monado path; it does not hard-block movement.
If a title appears to ignore the warning area, verify the Monado service is
running and `psvr2-chaperone` is enabled in `settings.env`.

## Room Setup UI tracks correctly but passthrough is beside or behind you

This is a raw-versus-standing tracking-universe mismatch, not lost Monado
tracking, a damaged play area, or a frozen camera. The PSVR2 Room Setup app
writes `chaperone_info.vrchap` for each saved play area. Monado's SteamVR-driver
loads that file at service startup and applies its saved standing yaw/
translation to HMD and controller poses. The camera feed is published in the
driver's raw tracking universe. Upstream xrizer currently maps OpenVR
`RawAndUncalibrated` to STAGE, so the problem appears only after a room
calibration has been saved and the runtime restarted.

This repository's xrizer patch implements a dedicated raw space by removing
that exact saved chaperone transform. `psvr2-room-setup` enables it only for
Room Setup; normal applications keep calibrated STAGE coordinates. Re-run
`./scripts/prepare-envision-runtime.sh`, rebuild the Envision profile, and then
`./install.sh --user` if the symptom returns after replacing the runtime.
Do not delete the calibrated play area or patch Unity's `GameAssembly.so`.

This setup also runs `psvr2-chaperone-sanity` at startup and after a room-setup
save. If a `standing.translation` entry is clearly invalid (for example a very
high Y offset), it is clamped back to a safe range with a timestamped backup
so the next boot does not place the HMD far above or below the floor.

## Error 102: vrclient shared library not found

Do not launch OpenVR games outside the wrapper. The per-game launch option must
contain `~/.local/bin/psvr2-fossvr-run %command%`. Run
`psvr2-sync-steam-vr-games` while Steam is stopped to restore VR-title options.

For **Keep Talking and Nobody Explodes**, this also restores the forced Proton
Experimental mapping. Its native Linux build does not contain VR support; do
not switch it back to the Linux runtime if you want to launch it in VR.
The helper additionally restores the known-good KTaNE profile (`VSync=0`, MSAA
off) while leaving the global 120 Hz / 170% PSVR2 target unchanged.

## Games do not appear in WayVR's Games tab after installation

This cache is refreshed automatically from Steam app manifest changes. Steam's
VR manifest is scanned once at desktop-session startup and again whenever the
headset runtime starts; this also covers registered non-Steam launchers such as
Revive games. WayVR reloads only when the resulting library changes.

If you installed new titles while already in VR and one is missing, run a non-
intrusive refresh:

```bash
psvr2-sync-steam-vr-games --discovery-only
```

The sync re-checks new installed entries and imports launchable binary entries
from `steamapps.vrmanifest`. Running it while WayVR is active refreshes the
dashboard automatically when the cache changes.

If a title still does not show in the Games tab, restart Monado/WayVR (`psvr2-fossvr-stop`
then `psvr2-fossvr-start`) so WayVR reloads the cache once with a clean runtime.

## SteamVR DRM lease error on GNOME Wayland

The normal play path here is Monado + xrizer, not Valve's compositor. Direct
DRM leasing is therefore not required for games. If deliberately testing
native SteamVR, GNOME/Mutter and the dGPU connector still need a working lease.

## Resolution and shimmer

PSVR2 panels are 2000×2040 per eye. At 170%, Monado recommends
3400×3468 per eye. This is intentional distortion supersampling, not a claim
that the panel has that native resolution. There is no ClearType equivalent
for VR; game TAA/MSAA, mip bias, render scale, lens sweet spot, and stable frame
timing matter. Leave the global default at 170% and change individual games.

## Screenshot chord does nothing

Press either PS button, then pull either trigger within half a second. The helper
targets an XWayland VR mirror, validates the resulting PNG, and refuses to fall
back to an unrelated desktop window. Check `wmctrl -lGpx`, run
`psvr2-screenshot --print-window` to inspect the selected mirror, and run
`psvr2-screenshot` directly to test capture. Successful captures are logged in
the user journal under the `psvr2-screenshot` tag and saved under
`~/Pictures/VR Screenshots/`. Native Wayland games without a mirror need their
own screenshot feature.

## Controller haptics not firing in game

This setup keeps Sense haptic support active in both Monado and XRizer:

- Monado maps Sense controllers to an OpenVR haptic output handle in
  `patches/monado-psvr2-sense.patch`.
- XRizer exposes haptic action targets (`/user/hand/.../output/haptic`) in the
  PSVR2-compatible bindings profile.

Run:

```bash
./scripts/verify-haptics.sh
```

If this script passes but a game is still silent, do a manual in-headset check:

1. Exit any menu and start a title with known force-feedback events:
   Superhot, Beat Saber, or Keep Talking and Nobody Explodes.
2. Trigger expected vibration moments (ammo impact, recoil, menu scroll/select).
3. If you only feel feedback in some titles, that game's Linux VR path is likely
   reducing or remapping vibration output.

For per-title issues, keep the same runtime and controller mapping; retune
game-specific settings instead.
