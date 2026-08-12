#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
commit=a0351bd00f208e9f7c7917d413de2accbf9208eb
for command in brew cargo git install; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done
root=${PSVR2_SETUP_ROOT:-"$HOME/.local/share/psvr2-setup"}
source_dir=${XR_CHAPERONE_SOURCE_DIR:-"$root/src/xr-chaperone"}
install_dir="$root/xr-chaperone"
patches=(
  "$repo/patches/xr-chaperone-proximity-warning.patch"
  "$repo/patches/xr-chaperone-configurable-colour.patch"
)

if [[ ! -d "$source_dir/.git" ]]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone https://github.com/FrostyCoolSlug/xr-chaperone "$source_dir"
fi
git -C "$source_dir" fetch origin "$commit"

# Normalize only the change managed by this repository, preserving any other
# source edits rather than hiding them with a hard reset.
for ((index=${#patches[@]} - 1; index >= 0; index--)); do
  patch=${patches[index]}
  if git -C "$source_dir" apply --reverse --check "$patch" 2>/dev/null; then
    git -C "$source_dir" apply --reverse "$patch"
  fi
done
if ! git -C "$source_dir" diff --quiet || ! git -C "$source_dir" diff --cached --quiet; then
  echo "xr-chaperone source contains unmanaged changes; refusing to overwrite them." >&2
  git -C "$source_dir" status --short >&2
  exit 1
fi
git -C "$source_dir" checkout --detach "$commit"
for patch in "${patches[@]}"; do
  if git -C "$source_dir" apply --check "$patch" 2>/dev/null; then
    git -C "$source_dir" apply "$patch"
  elif ! git -C "$source_dir" apply --reverse --check "$patch" 2>/dev/null; then
    echo "xr-chaperone patch does not apply cleanly: $patch" >&2
    exit 1
  fi
done
git -C "$source_dir" diff --check

brew_prefix=$(brew --prefix)
env PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig" \
    SHADERC_LIB_DIR="$brew_prefix/opt/shaderc/lib" \
    LIBRARY_PATH="$brew_prefix/lib" \
    cargo test --locked --manifest-path "$source_dir/Cargo.toml"
env PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig" \
    SHADERC_LIB_DIR="$brew_prefix/opt/shaderc/lib" \
    LIBRARY_PATH="$brew_prefix/lib" \
    cargo build --locked --manifest-path "$source_dir/Cargo.toml" --release

mkdir -p "$install_dir"
install -m 0755 "$source_dir/target/release/xr-chaperone" "$install_dir/xr-chaperone"
echo "Installed pinned xr-chaperone $commit to $install_dir/xr-chaperone"
