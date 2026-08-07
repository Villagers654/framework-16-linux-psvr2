#!/usr/bin/bash
set -u

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/psvr2-common.sh
source "$repo/lib/psvr2-common.sh"

failed=0
check() { if "$@"; then printf 'OK   %s\n' "$*"; else printf 'FAIL %s\n' "$*"; failed=1; fi; }
check test -x "$HOME/.local/bin/psvr2-fossvr-start"
check test -x "$HOME/.local/bin/psvr2-screenshot"
check bash -c 'test "$(PSVR2_SCREENSHOT_WINDOW_LIST="$1" "$HOME/.local/bin/psvr2-screenshot" --print-window)" = 0x1' _ \
    '0x1 0 1 0 0 3840 2400 game.Game host VR Game'
check test -x "$HOME/.local/bin/psvr2-spectator"
check test -x "$HOME/.local/share/psvr2-setup/wayvr/wayvr"
check grep -aFq 'PSVR2 screenshot chord pressed' "$HOME/.local/share/psvr2-setup/wayvr/wayvr"
check test -x "$HOME/.local/share/psvr2-setup/unity-setup/PSVR2Toolkit.UnitySetup.x86_64"
check test -x "$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
check test -f "$HOME/.local/share/envision/psvr2-toolkit-monado/xrizer/target/release/libxrizer.so"
check grep -aFq 'Raw tracking space removes PSVR2 chaperone' "$HOME/.local/share/envision/psvr2-toolkit-monado/xrizer/target/release/libxrizer.so"
check grep -Fq 'XRIZER_FORCE_RAW_TRACKING_SPACE=1' "$HOME/.local/bin/psvr2-room-setup"
check grep -Fq 'PSVR2 play area saved' "$HOME/.local/bin/psvr2-room-setup"
check bash -c 'bash "$1"' _ "$repo/scripts/verify-haptics.sh"
check bash -c 'getcap "$1" | grep -Fq "cap_sys_nice=eip"' _ \
    "$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
check grep -Fq 'U_PACING_COMP_MIN_TIME_MS' "$HOME/.local/bin/psvr2-monado-service"
check test "$PSVR2_REFRESH_RATE" = 120
check test "$PSVR2_RENDER_SCALE" = 170
check test "$PSVR2_SPECTATOR_ENABLE" = 0 -o "$PSVR2_SPECTATOR_ENABLE" = 1
check grep -aFq 'PSVR2 Spectator View' "$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
check python3 -m json.tool "$HOME/.local/share/psvr2-setup/unity-setup/PSVR2Toolkit.UnitySetup_Data/StreamingAssets/SteamVR/bindings_oculus_touch.json" >/dev/null
check python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["steamvr"]; assert s["preferredRefreshRate"] == 120 and s["supersampleManualOverride"] is True and s["supersampleScale"] == 1.0' "$STEAM_ROOT/config/steamvr.vrsettings"
check systemctl --user is-enabled --quiet psvr2-autostart-monitor.service
check grep -aFq 'PSVR2 Room Setup' "$HOME/.local/share/psvr2-setup/wayvr/wayvr"
lsusb -d 054c:0cde >/dev/null || echo 'WARN PSVR2 adapter is not currently connected'
exit "$failed"
