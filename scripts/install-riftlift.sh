#!/usr/bin/bash
set -euo pipefail

# RiftLift owns the Meta/Revive compatibility stack. This PSVR2 integration
# consumes its tagged installer exactly like any other third-party application.
tag=v0.2.0
commit=ead48b8fe4bfccf428337c72251763dfa71082f4
source_dir=${RIFTLIFT_SOURCE_DIR:-"${XDG_DATA_HOME:-$HOME/.local/share}/psvr2-setup/src/riftlift"}

command -v git >/dev/null 2>&1 || { echo "Missing required command: git" >&2; exit 1; }

if [[ ! -d "$source_dir/.git" ]]; then
    mkdir -p "$(dirname "$source_dir")"
    git clone --branch "$tag" --depth 1 https://github.com/Villagers654/RiftLift.git "$source_dir"
else
    if ! git -C "$source_dir" diff --quiet || ! git -C "$source_dir" diff --cached --quiet; then
        echo "Refusing to overwrite unmanaged RiftLift changes in $source_dir" >&2
        exit 1
    fi
    git -C "$source_dir" fetch --depth 1 origin "refs/tags/$tag:refs/tags/$tag"
    git -C "$source_dir" checkout --detach "$tag"
fi

actual_commit=$(git -C "$source_dir" rev-parse HEAD)
if [[ "$actual_commit" != "$commit" ]]; then
    echo "RiftLift $tag resolved to unexpected commit $actual_commit" >&2
    exit 1
fi

"$source_dir/install.sh"
