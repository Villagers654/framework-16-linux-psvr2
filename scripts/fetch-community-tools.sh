#!/usr/bin/bash
set -euo pipefail

root=${PSVR2_SETUP_ROOT:-"$HOME/.local/share/psvr2-setup"}
downloads="$root/downloads"
mkdir -p "$downloads"

fetch_extract() {
  local name=$1 url=$2 destination=$3 archive="$downloads/$name.zip"
  curl --fail --location --retry 3 --output "$archive" "$url"
  mkdir -p "$destination"
  unzip -o "$archive" -d "$destination"
}

fetch_appimage() {
  local name=$1 url=$2 destination=$3 archive="$downloads/$name.zip"
  echo "Downloading xr-chaperone AppImage to $destination"
  curl --fail --location --retry 3 --output "$archive" "$url"
  mkdir -p "$destination"
  rm -f "$destination"/*.AppImage "$destination"/*.appimage 2>/dev/null || true
  unzip -o "$archive" -d "$destination"
  local image
  image=$(find "$destination" -maxdepth 1 -type f \( -iname '*.AppImage' -o -iname '*.appimage' \) | head -n 1 || true)
  if [[ -z "$image" ]]; then
    echo "Failed to locate an xr-chaperone AppImage in $destination" >&2
    exit 1
  fi
  mv -f "$image" "$destination/xr-chaperone.AppImage"
  chmod +x "$destination/xr-chaperone.AppImage"
}

fetch_extract toolkit \
  https://github.com/BnuuySolutions/PSVR2Toolkit/releases/download/v1.0.0-experimental-1/PSVR2TK-win64-Ignition.zip \
  "$root/toolkit"
fetch_extract ignition \
  https://github.com/BnuuySolutions/Ignition/releases/download/v1.0.0/Ignition-Linux-Windows.zip \
  "$root/ignition"
fetch_extract unity-setup \
  https://github.com/BnuuySolutions/PSVR2Toolkit.UnitySetup/releases/download/v1.1.0/PSVR2Toolkit.UnitySetup-Linux.zip \
  "$root/unity-setup"
fetch_extract steamvr-linux-fixes \
  https://github.com/BnuuySolutions/SteamVRLinuxFixes/releases/download/v0.1.4/VK_LAYER_BNUUY_steamvr_linux_fixes.zip \
  "$root/steamvr-linux-fixes"

fetch_appimage xr-chaperone \
  https://nightly.link/FrostyCoolSlug/xr-chaperone/workflows/release.yml/main/xr-chaperone-x86_64.zip \
  "$root/xr-chaperone"

find "$root/unity-setup" -name 'PSVR2Toolkit.UnitySetup.x86_64' -exec chmod 0755 {} +
echo "Downloaded pinned community tools to $root"
echo "Review upstream licenses in each extracted directory."
