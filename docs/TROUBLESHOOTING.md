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

## Error 102: vrclient shared library not found

Do not launch OpenVR games outside the wrapper. The per-game launch option must
contain `~/.local/bin/psvr2-fossvr-run %command%`. Run
`psvr2-sync-steam-vr-games` while Steam is stopped to restore VR-title options.

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

The helper targets an XWayland VR mirror. Check `wmctrl -lGpx` and run
`psvr2-screenshot` directly. Native Wayland games without a mirror need their
own screenshot feature. Files are saved under `~/Pictures/VR Screenshots/`.
