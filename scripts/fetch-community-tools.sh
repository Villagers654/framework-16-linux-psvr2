#!/usr/bin/bash
set -euo pipefail

for command in curl install mktemp mv sha256sum unzip; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

root=${PSVR2_SETUP_ROOT:-"$HOME/.local/share/psvr2-setup"}
downloads="$root/downloads"
install -d -m 0755 "$downloads"

fetch_extract() {
  local name=$1 url=$2 expected_sha256=$3 destination=$4
  local archive="$downloads/$name.zip"
  local partial="$archive.partial"
  local stage
  [[ "$destination" == "$root/"* ]] || {
    echo "Refusing to extract outside PSVR2_SETUP_ROOT: $destination" >&2
    exit 1
  }
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
    --output "$partial" "$url"
  printf '%s  %s\n' "$expected_sha256" "$partial" | sha256sum --check --status || {
    rm -f -- "$partial"
    echo "Checksum verification failed for $name" >&2
    exit 1
  }
  mv -f -- "$partial" "$archive"
  stage=$(mktemp -d "$root/.${name}.XXXXXX")
  unzip -q "$archive" -d "$stage"
  rm -rf -- "$destination"
  mv -- "$stage" "$destination"
}

fetch_extract toolkit \
  https://github.com/BnuuySolutions/PSVR2Toolkit/releases/download/v1.0.0-experimental-1/PSVR2TK-win64-Ignition.zip \
  d4ca4490a1d4196a913b06cacc75e1debf93b4deb5f20690049db0736c87e144 \
  "$root/toolkit"
fetch_extract ignition \
  https://github.com/BnuuySolutions/Ignition/releases/download/v1.0.0/Ignition-Linux-Windows.zip \
  60906375bdc56255c8ad80a87750425fb06039fd4011bb2a16d320bee51163c8 \
  "$root/ignition"
fetch_extract unity-setup \
  https://github.com/BnuuySolutions/PSVR2Toolkit.UnitySetup/releases/download/v1.1.0/PSVR2Toolkit.UnitySetup-Linux.zip \
  5e223773e6615f71b9496393ae9e1d74df43cab2a30e67e1a1b389e4cc8ad7da \
  "$root/unity-setup"
find "$root/unity-setup" -name 'PSVR2Toolkit.UnitySetup.x86_64' -exec chmod 0755 {} +
echo "Downloaded pinned community tools to $root"
echo "Build the pinned chaperone source with ./scripts/build-xr-chaperone.sh."
echo "Review upstream licenses in each extracted directory."
