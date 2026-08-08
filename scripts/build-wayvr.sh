#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for command in brew cargo git install; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done
source_dir=${WAYVR_SOURCE_DIR:-"$HOME/.local/share/psvr2-setup/src/wayvr"}
install_dir=${PSVR2_SETUP_ROOT:-"$HOME/.local/share/psvr2-setup"}/wayvr

if [[ ! -d "$source_dir/.git" ]]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone https://github.com/wayvr-org/wayvr "$source_dir"
fi
git -C "$source_dir" fetch origin
git -C "$source_dir" checkout --detach d93b74cc8aa01ea17d72d46ce016e47286409f92
if git -C "$source_dir" apply --check "$repo/patches/wayvr-psvr2-dashboard.patch" 2>/dev/null; then
  git -C "$source_dir" apply "$repo/patches/wayvr-psvr2-dashboard.patch"
elif git -C "$source_dir" apply --reverse --check \
  "$repo/patches/wayvr-psvr2-dashboard.patch" 2>/dev/null; then
  echo "WayVR patch is already applied."
else
  echo "WayVR patch does not apply cleanly to the pinned source." >&2
  exit 1
fi
git -C "$source_dir" diff --check

brew_prefix=$(brew --prefix)
pkg_config_path="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig"
for module in alsa dav1d dbus-1 libpipewire-0.3 openssl xkbcommon; do
  if ! PKG_CONFIG_PATH="$pkg_config_path" pkg-config --exists "$module"; then
    echo "Missing required Homebrew pkg-config module: $module" >&2
    echo "Install the complete WayVR toolchain documented in README.md." >&2
    exit 1
  fi
done
if [[ ! -r "$brew_prefix/include/vulkan/vulkan.h" || \
      ! -e "$brew_prefix/lib/libvulkan.so" ]]; then
  echo "Missing required Homebrew Vulkan headers or loader." >&2
  echo "Install vulkan-headers and vulkan-loader as documented in README.md." >&2
  exit 1
fi
env PKG_CONFIG_PATH="$pkg_config_path" \
    CMAKE_PREFIX_PATH="$brew_prefix" \
    SHADERC_LIB_DIR="$brew_prefix/opt/shaderc/lib" LIBRARY_PATH="$brew_prefix/lib" \
    cargo build --locked --manifest-path "$source_dir/Cargo.toml" --release -p wayvr
mkdir -p "$install_dir"
install -m 0755 "$source_dir/target/release/wayvr" "$install_dir/wayvr"
echo "Installed patched WayVR to $install_dir/wayvr"
