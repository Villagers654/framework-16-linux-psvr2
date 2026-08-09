#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/psvr2-common.sh
source "$repo/lib/psvr2-common.sh"

for command in brew cargo cmake grep nm strings; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

monado_source="$ENVISION_PROFILE_ROOT/xrservice"
xrizer_source="$ENVISION_PROFILE_ROOT/xrizer"
[[ -d "$monado_source/.git" && -d "$xrizer_source/.git" ]] || {
  echo "Prepared Envision sources were not found; run ./scripts/prepare-envision-runtime.sh first." >&2
  exit 1
}

brew_prefix=$(brew --prefix)
udev_prefix=$(brew --prefix systemd)
build_dir="$monado_source/build"

for formula in eigen glslang hidapi jpeg-turbo libusb sdl2-compat systemd vulkan-headers vulkan-loader; do
  brew --prefix "$formula" >/dev/null 2>&1 || {
    echo "Missing Homebrew formula: $formula" >&2
    exit 1
  }
done

# The host pkg-config keeps distribution graphics integration (notably XRandR)
# visible while Homebrew provides the rapidly changing build dependencies.
PKG_CONFIG=/usr/bin/pkg-config \
PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig" \
cmake -S "$monado_source" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$MONADO_PREFIX" \
  -DCMAKE_PREFIX_PATH="$brew_prefix;$udev_prefix" \
  -DCMAKE_INSTALL_RPATH="$brew_prefix/lib" \
  -DXRT_HAVE_SYSTEM_CJSON=NO \
  -DUDEV_INCLUDE_DIR="$udev_prefix/include" \
  -DUDEV_LIBRARY="$udev_prefix/lib/libudev.so" \
  -DVulkan_INCLUDE_DIR="$brew_prefix/include" \
  -DVulkan_LIBRARY="$brew_prefix/lib/libvulkan.so" \
  -DXRT_FEATURE_DEBUG_GUI=OFF \
  -DXRT_FEATURE_OPENXR=ON \
  -DXRT_FEATURE_SERVICE=ON \
  -DXRT_BUILD_DRIVER_PSSENSE=ON \
  -DXRT_BUILD_DRIVER_PSVR2=OFF \
  -DXRT_BUILD_DRIVER_STEAMVR_LIGHTHOUSE=ON

cache="$build_dir/CMakeCache.txt"
for required in \
  XRT_BUILD_DRIVER_PSSENSE \
  XRT_BUILD_DRIVER_STEAMVR_LIGHTHOUSE \
  XRT_FEATURE_OPENXR \
  XRT_FEATURE_SERVICE; do
  grep -Eq "^${required}(:[^=]+)?=ON$" "$cache" || {
    echo "Required Monado feature was not enabled: $required" >&2
    exit 1
  }
done
grep -Eq '^XRT_BUILD_DRIVER_PSVR2(:[^=]+)?=OFF$' "$cache" || {
  echo "Native Monado PSVR2 must be disabled when Toolkit + Ignition is selected" >&2
  exit 1
}
grep -Eq '^XRT_FEATURE_DEBUG_GUI(:[^=]+)?=OFF$' "$cache" || {
  echo "Monado debug GUI must remain disabled in the production runtime" >&2
  exit 1
}

LIBRARY_PATH="$brew_prefix/lib" cmake --build "$build_dir"
cmake --install "$build_dir"

service="$MONADO_PREFIX/bin/monado-service"
[[ -x "$service" ]] || { echo "Monado service was not installed." >&2; exit 1; }
nm -C "$service" | grep 'steamvr_open_system' >/dev/null || {
  echo "SteamVR-driver bridge is missing from monado-service." >&2
  exit 1
}
ldd_output=$(ldd "$service")
if grep 'not found' <<<"$ldd_output" >/dev/null; then
  echo "monado-service has unresolved shared libraries:" >&2
  grep 'not found' <<<"$ldd_output" >&2
  exit 1
fi

(cd "$xrizer_source" && cargo xbuild --release)
[[ -s "$xrizer_source/target/release/libxrizer.so" ]] || {
  echo "xrizer release library was not produced." >&2
  exit 1
}

echo "Pinned Monado and xrizer runtimes built and verified."
