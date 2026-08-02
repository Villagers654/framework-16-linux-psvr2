#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=${WAYVR_SOURCE_DIR:-"$HOME/.local/share/psvr2-setup/src/wayvr"}
install_dir=${PSVR2_SETUP_ROOT:-"$HOME/.local/share/psvr2-setup"}/wayvr

if [[ ! -d "$source_dir/.git" ]]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone https://github.com/wayvr-org/wayvr "$source_dir"
fi
git -C "$source_dir" fetch origin
git -C "$source_dir" checkout 5723c3c1df31b332a54f59161762d41dd3bd4ff2
git -C "$source_dir" apply --check "$repo/patches/wayvr-psvr2-dashboard.patch" 2>/dev/null && \
  git -C "$source_dir" apply "$repo/patches/wayvr-psvr2-dashboard.patch" || true

brew_prefix=$(brew --prefix 2>/dev/null || true)
env PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig" \
    SHADERC_LIB_DIR="$brew_prefix/opt/shaderc/lib" LIBRARY_PATH="$brew_prefix/lib" \
    cargo build --manifest-path "$source_dir/Cargo.toml" --release -p wayvr
mkdir -p "$install_dir"
install -m 0755 "$source_dir/target/release/wayvr" "$install_dir/wayvr"
echo "Installed patched WayVR to $install_dir/wayvr"
