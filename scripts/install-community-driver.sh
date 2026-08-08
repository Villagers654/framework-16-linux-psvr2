#!/usr/bin/bash
set -euo pipefail

for command in cmp install jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

setup_root=${PSVR2_SETUP_ROOT:-"$HOME/.local/share/psvr2-setup"}
steam_root=${STEAM_ROOT:-"$HOME/.local/share/Steam"}
toolkit="$setup_root/toolkit"
ignition="$setup_root/ignition"
driver="$steam_root/steamapps/common/PlayStation VR2 App/SteamVR_Plug-In"
win64="$driver/bin/win64"
official="$win64/driver_playstation_vr2_orig.dll"
active="$win64/driver_playstation_vr2.dll"
steam_settings="$steam_root/config/steamvr.vrsettings"
psvr2_config="$steam_root/config/playstation_vr2"

[[ -f "$driver/driver.vrdrivermanifest" ]] || {
  echo "PlayStation VR2 SteamVR driver is not installed at: $driver" >&2
  exit 1
}
for file in driver_playstation_vr2.dll libcrossipc.dll libcrossipc.so \
  libpsvr2_toolkit_capi.so libusb-1.0.dll psvr2_toolkit_capi.dll; do
  [[ -f "$toolkit/$file" ]] || {
    echo "Missing PSVR2 Toolkit file: $toolkit/$file" >&2
    exit 1
  }
done
[[ -x "$ignition/install_ignition.sh" && -f "$ignition/libdriver_ignition.so" ]] || {
  echo "Ignition is incomplete at: $ignition" >&2
  exit 1
}

install -d -m 0755 "$win64"
# Sony's driver writes its map and chaperone files here but does not create the
# parent directory on a fresh Linux Steam installation.
install -d -m 0755 "$psvr2_config"
if [[ ! -f "$official" ]]; then
  [[ -f "$active" ]] || {
    echo "Sony's original driver is missing: $active" >&2
    exit 1
  }
  if cmp -s "$active" "$toolkit/driver_playstation_vr2.dll"; then
    echo "Refusing to invent a backup: active driver is already Toolkit but Sony original is absent." >&2
    exit 1
  fi
  mv -- "$active" "$official"
fi

for file in driver_playstation_vr2.dll libcrossipc.dll libcrossipc.so \
  libpsvr2_toolkit_capi.so libusb-1.0.dll psvr2_toolkit_capi.dll; do
  install -m 0644 "$toolkit/$file" "$win64/$file"
done

"$ignition/install_ignition.sh" "$driver"
chmod 0755 "$driver/bin/linux64/proton" \
  "$driver/bin/linux64/launch_serverhelper.sh" \
  "$driver/bin/linux64/driver_install.sh" \
  "$driver/bin/linux64/driver_uninstall.sh"

# Toolkit's experimental LED synchronizer is less reliable on this hardware
# than the driver's standard synchronization path. Preserve every unrelated
# SteamVR setting while selecting the path verified with both Sense controllers.
install -d -m 0755 "$(dirname "$steam_settings")"
settings_tmp=$(mktemp "${steam_settings}.XXXXXX")
if [[ -f "$steam_settings" ]]; then
  jq '.playstation_vr2_ex = ((.playstation_vr2_ex // {}) + {
    useToolkitSync: false,
    useEnhancedHaptics: true
  })' "$steam_settings" > "$settings_tmp"
else
  jq -n '{playstation_vr2_ex: {
    useToolkitSync: false,
    useEnhancedHaptics: true
  }}' > "$settings_tmp"
fi
chmod 0644 "$settings_tmp"
mv -- "$settings_tmp" "$steam_settings"

jq -e '.name == "playstation_vr2"' "$driver/driver.vrdrivermanifest" >/dev/null
[[ -L "$driver/bin/linux64/driver_playstation_vr2.so" ]] || {
  echo "Ignition did not create the Linux driver bridge." >&2
  exit 1
}
echo "PSVR2 Toolkit and Ignition installed into the Sony driver tree."
