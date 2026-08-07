#!/usr/bin/bash
set -u

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail=0
check() {
    local name=$1
    shift
    if "$@"; then
        printf 'OK   %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        fail=1
    fi
}

check "Monado sense haptic output mapping in repo patch" bash -c \
    'grep -qF "XRT_DEVICE_TOUCH_CONTROLLER" "$0" && grep -qF "XRT_OUTPUT_NAME_TOUCH_HAPTIC" "$0"' \
    "$repo/patches/monado-psvr2-sense.patch"

check "PSVR2 Unity compatibility profile remains whitelisted in Monado haptic handler" bash -c \
    'grep -qF "playstation_vr2_sense_controller" "$0"' \
    "$repo/patches/monado-psvr2-sense.patch"

check "WayVR controller haptic output paths are in the patched dashboard actions" bash -c \
    'grep -qF "/user/hand/left/output/haptic" "$0" && grep -qF "/user/hand/right/output/haptic" "$0"' \
    "$repo/patches/wayvr-psvr2-dashboard.patch"

if [[ -d "$HOME/.local/share/envision/psvr2-toolkit-monado/xrizer/src" ]]; then
    check "local xrizer source still has haptic action wiring" bash -c \
        'rg -q "/user/hand/(left|right)/output/haptic|fn legacy_haptic" "$0/src/input.rs" "$0/src/input/legacy.rs" "$0/src/input/action_manifest.rs"' \
        "$HOME/.local/share/envision/psvr2-toolkit-monado/xrizer"
else
    echo "WARN  local xrizer source is not present for deeper haptics validation: $HOME/.local/share/envision/psvr2-toolkit-monado/xrizer"
fi

monado_prefix="$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado"
if [[ -x "$monado_prefix/bin/monado-service" ]]; then
    check "Monado runtime package is present" true
else
    check "Monado runtime package is present" false
fi

if [[ -f "$repo/patches/monado-psvr2-sense.patch" ]]; then
    xrizer_src="$HOME/.local/share/envision/psvr2-toolkit-monado/xrizer"
    if command -v cargo >/dev/null && [[ -x "$xrizer_src/target/release/xrizer" || -f "$xrizer_src/target/release/libxrizer.so" ]]; then
        check "xrizer legacy haptics test passes (requires local Rust toolchain and source rebuild)" bash -c \
            'cd "$0" && cargo test legacy_haptic -- --nocapture' \
            "$xrizer_src"
    else
        echo "WARN  skipping xrizer unit test run (toolchain/bin not available or runtime not built)"
    fi
fi

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi

echo "Haptic checks passed. For in-game confirmation, launch any VR title that emits haptics (Superhot, Beat Saber, etc.) and confirm tactile feedback when expected."
exit 0
