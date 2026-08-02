#!/usr/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
setup_root=${PSVR2_ROOM_SETUP_DIR:-"$HOME/.local/share/psvr2-setup/unity-setup"}
binding_dir="$setup_root/PSVR2Toolkit.UnitySetup_Data/StreamingAssets/SteamVR"
target="$binding_dir/bindings_oculus_touch.json"

[[ -d "$binding_dir" ]] || {
    echo "Room Setup not found at: $setup_root" >&2
    echo "Install PSVR2Toolkit.UnitySetup, or set PSVR2_ROOM_SETUP_DIR." >&2
    exit 1
}

if [[ -f "$target" && ! -f "$target.upstream" ]]; then
    cp -- "$target" "$target.upstream"
fi
install -m 0644 "$repo_dir/config/room-setup-bindings-oculus-touch.json" "$target"
python3 -m json.tool "$target" >/dev/null
echo "Installed xrizer/Sense bindings for PSVR2 Room Setup."
