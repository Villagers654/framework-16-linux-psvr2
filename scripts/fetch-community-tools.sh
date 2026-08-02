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

fetch_extract toolkit \
  https://github.com/BnuuySolutions/PSVR2Toolkit/releases/download/v1.0.0-experimental-1/PSVR2TK-win64-Ignition.zip \
  "$root/toolkit"
fetch_extract ignition \
  https://github.com/BnuuySolutions/Ignition/releases/download/v1.0.0/Ignition-Linux-Windows.zip \
  "$root/ignition"
fetch_extract unity-setup \
  https://github.com/BnuuySolutions/PSVR2Toolkit.UnitySetup/releases/download/v1.0.0/PSVR2Toolkit.UnitySetup-Linux.zip \
  "$root/unity-setup"
fetch_extract steamvr-linux-fixes \
  https://github.com/BnuuySolutions/SteamVRLinuxFixes/releases/download/v0.1.4/VK_LAYER_BNUUY_steamvr_linux_fixes.zip \
  "$root/steamvr-linux-fixes"

find "$root/unity-setup" -name 'PSVR2Toolkit.UnitySetup.x86_64' -exec chmod 0755 {} +
echo "Downloaded pinned community tools to $root"
echo "Review upstream licenses in each extracted directory."
