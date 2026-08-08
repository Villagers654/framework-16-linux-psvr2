#!/usr/bin/bash
set -euo pipefail

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

if [[ ! -d "$source_dir/.git" ]]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone https://github.com/FrostyCoolSlug/xr-chaperone "$source_dir"
fi
git -C "$source_dir" fetch origin "$commit"
git -C "$source_dir" checkout --detach "$commit"

brew_prefix=$(brew --prefix)
env PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig" \
    SHADERC_LIB_DIR="$brew_prefix/opt/shaderc/lib" \
    LIBRARY_PATH="$brew_prefix/lib" \
    cargo build --locked --manifest-path "$source_dir/Cargo.toml" --release

mkdir -p "$install_dir"
install -m 0755 "$source_dir/target/release/xr-chaperone" "$install_dir/xr-chaperone"
echo "Installed pinned xr-chaperone $commit to $install_dir/xr-chaperone"
