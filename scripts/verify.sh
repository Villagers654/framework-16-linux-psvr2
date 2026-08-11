#!/usr/bin/bash
set -u

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/psvr2-common.sh
source "$repo/lib/psvr2-common.sh"

failed=0
check() { if "$@"; then printf 'OK   %s\n' "$*"; else printf 'FAIL %s\n' "$*"; failed=1; fi; }
check test -x "$HOME/.local/bin/psvr2-fossvr-start"
check test -x "$HOME/.local/bin/psvr2-usb-reset"
check command -v usbreset
check test -f "$HOME/.config/environment.d/60-psvr2-openxr.conf"
check grep -Fq 'PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1' \
  "$HOME/.config/environment.d/60-psvr2-openxr.conf"
check test -x "$HOME/.local/bin/psvr2-controller-disconnect"
check test -x "$HOME/.local/bin/psvr2-screenshot"
check test -x "$HOME/.local/lib/psvr2-linux/psvr2-screenshot-listener"
check systemctl --user is-active --quiet psvr2-screenshot-listener.service
check test -x "$HOME/.local/bin/psvr2-chaperone"
check test -x "$HOME/.local/bin/psvr2-import-boundary"
check bash -c 'test "$(PSVR2_SCREENSHOT_WINDOW_LIST="$1" "$HOME/.local/bin/psvr2-screenshot" --print-window)" = 0x1' _ \
    '0x1 0 1 0 0 3840 2400 monado-service.monado-service host PSVR2 Spectator View'
if [[ "$PSVR2_CHAPERONE_ENABLE" == 1 ]]; then
  check test -x "${PSVR2_CHAPERONE_BINARY:-$HOME/.local/share/psvr2-setup/xr-chaperone/xr-chaperone}"
fi
check test -x "$HOME/.local/share/psvr2-setup/wayvr/wayvr"
check grep -aFq 'PSVR2 screenshot chord pressed' "$HOME/.local/share/psvr2-setup/wayvr/wayvr"
check test -x "$HOME/.local/share/psvr2-setup/unity-setup/PSVR2Toolkit.UnitySetup.x86_64"
check test -d "$HOME/.local/share/Steam/config/playstation_vr2"
check test -f "$HOME/.local/share/Steam/steamapps/common/PlayStation VR2 App/SteamVR_Plug-In/bin/win64/driver_playstation_vr2_orig.dll"
check test -L "$HOME/.local/share/Steam/steamapps/common/PlayStation VR2 App/SteamVR_Plug-In/bin/linux64/driver_playstation_vr2.so"
check test -x "$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
check bash -c 'if command -v objdump >/dev/null 2>&1; then objdump -t "$1" 2>/dev/null | grep -aFq "steamvr_open_system"; else strings "$1" | grep -aFq "steamvr_open_system"; fi' _ \
    "$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
check bash -c 'configured=$(jq -r ".user_profiles[] | select(.uuid==\"psvr2-toolkit-monado\") | .xrservice_cmake_flags.XRT_BUILD_DRIVER_PSVR2 // \"\" " "$1" 2>/dev/null || true); [[ "$configured" == "OFF" ]]' _ \
    "$HOME/.config/envision/envision.json"
check bash -c 'configured=$(jq -r ".user_profiles[] | select(.uuid==\"psvr2-toolkit-monado\") | .xrservice_cmake_flags.XRT_BUILD_DRIVER_PSSENSE // \"\" " "$1" 2>/dev/null || true); [[ "$configured" == "ON" ]]' _ \
    "$HOME/.config/envision/envision.json"
check test -f "$HOME/.local/share/envision/psvr2-toolkit-monado/riftlift/components/xrizer/target/release/libxrizer.so"
check grep -aFq 'Raw tracking space removes chaperone' "$HOME/.local/share/envision/psvr2-toolkit-monado/riftlift/components/xrizer/target/release/libxrizer.so"
check grep -Fq 'XRIZER_FORCE_RAW_TRACKING_SPACE=1' "$HOME/.local/bin/psvr2-room-setup"
check grep -Fq 'PSVR2 play area saved' "$HOME/.local/bin/psvr2-room-setup"
check grep -Fq 'psvr2-room-setup.service' "$repo/patches/wayvr-psvr2-dashboard.patch"
check grep -Fq 'registered_nonsteam_vr_apps' "$repo/patches/wayvr-nonsteam-vr-library.patch"
check grep -Fq 'FrontendTask::HideDashboard' "$repo/patches/wayvr-dismiss-dashboard-on-launch.patch"
check grep -Fq 'SetDashboardVisible' "$repo/patches/wayvr-game-lifecycle-dashboard.patch"
check bash -c 'bash "$1"' _ "$repo/scripts/verify-haptics.sh"
monado_service="$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
if ! getcap "$monado_service" | grep -Fq 'cap_sys_nice=eip'; then
  echo "WARN monado-service lacks optional cap_sys_nice; run sudo ./install.sh --system for realtime scheduling"
fi
check grep -Fq 'U_PACING_COMP_MIN_TIME_MS' "$HOME/.local/bin/psvr2-monado-service"
check test "$PSVR2_RENDER_SCALE" = 170
check python3 -m json.tool "$HOME/.local/share/psvr2-setup/unity-setup/PSVR2Toolkit.UnitySetup_Data/StreamingAssets/SteamVR/bindings_oculus_touch.json" >/dev/null
check systemctl --user is-enabled --quiet psvr2-autostart-monitor.service
check systemctl --user is-enabled --quiet psvr2-steam-vr-sync.path
check systemctl --user is-enabled --quiet psvr2-steam-vr-sync.timer
check grep -aFq 'PSVR2 Room Setup' "$HOME/.local/share/psvr2-setup/wayvr/wayvr"
lsusb -d 054c:0cde >/dev/null || echo 'WARN PSVR2 adapter is not currently connected'
exit "$failed"
