# Troubleshooting

## Black headset, WayVR absent, or controllers missing

```bash
psvr2-fossvr-stop
psvr2-fossvr-start
systemctl --user status psvr2-fossvr.service psvr2-fossvr-wayvr.service
journalctl --user -u psvr2-fossvr.service -n 150 --no-pager
```

Confirm both controller HID devices exist with `psvr2-controller-preflight`.
If BlueZ says connected but no HID device exists, fill the optional controller
MACs in the private settings file and rerun the preflight.

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

## Room Setup UI tracks correctly but passthrough is beside or behind you

This is a raw-versus-standing tracking-universe mismatch, not lost Monado
tracking, a damaged play area, or a frozen camera. Monado's SteamVR-driver
bridge loads `chaperone_info.vrchap` at service startup and applies its saved
standing yaw/translation to HMD and controller poses. The Toolkit camera feed
remains in the driver's raw tracking universe. Upstream xrizer currently maps
OpenVR `RawAndUncalibrated` to STAGE, so the problem appears only after a room
calibration has been saved and the runtime restarted.

This repository's xrizer patch implements a dedicated raw space by removing
that exact saved chaperone transform. `psvr2-room-setup` enables it only for
UnitySetup; normal applications keep calibrated STAGE coordinates. Re-run
`./scripts/prepare-envision-runtime.sh`, rebuild the Envision profile, and then
`./install.sh --user` if the symptom returns after replacing the runtime.
Do not delete the calibrated play area or patch Unity's `GameAssembly.so`.

## Error 102: vrclient shared library not found

Do not launch OpenVR games outside the wrapper. The per-game launch option must
contain `~/.local/bin/psvr2-fossvr-run %command%`. Run
`psvr2-sync-steam-vr-games` while Steam is stopped to restore VR-title options.

For **Keep Talking and Nobody Explodes**, this also restores the forced Proton
Experimental mapping. Its native Linux build does not contain VR support; do
not switch it back to the Linux runtime if you want to launch it in VR.
The helper additionally restores the known-good KTaNE profile (`VSync=0`, MSAA
off) while leaving the global 120 Hz / 170% PSVR2 target unchanged.

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

Press either PS button, then pull either trigger within two seconds. The helper
targets an XWayland VR mirror, validates the resulting PNG, and refuses to fall
back to an unrelated desktop window. Check `wmctrl -lGpx`, run
`psvr2-screenshot --print-window` to inspect the selected mirror, and run
`psvr2-screenshot` directly to test capture. Successful captures are logged in
the user journal under the `psvr2-screenshot` tag and saved under
`~/Pictures/VR Screenshots/`. Native Wayland games without a mirror need their
own screenshot feature.
