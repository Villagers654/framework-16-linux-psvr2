#!/usr/bin/bash

config_file="${PSVR2_CONFIG:-$HOME/.config/psvr2-linux/settings.env}"
if [[ -r "$config_file" ]]; then
    config_uid=$(stat -c '%u' "$config_file" 2>/dev/null || printf -- '-1')
    config_mode=$(stat -c '%a' "$config_file" 2>/dev/null || printf '777')
    if [[ "$config_uid" != "$(id -u)" ]] || (( (8#$config_mode & 022) != 0 )); then
        echo "Refusing unsafe PSVR2 config (must be user-owned and not group/world-writable): $config_file" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck disable=SC1090
    source "$config_file"
fi

PSVR2_RENDER_SCALE="${PSVR2_RENDER_SCALE:-170}"
PSVR2_SETUP_ROOT="${PSVR2_SETUP_ROOT:-$HOME/.local/share/psvr2-setup}"
PSVR2_SPECTATOR_ENABLE="${PSVR2_SPECTATOR_ENABLE:-1}"
PSVR2_CHAPERONE_ENABLE="${PSVR2_CHAPERONE_ENABLE:-1}"
PSVR2_CHAPERONE_BINARY="${PSVR2_CHAPERONE_BINARY:-$PSVR2_SETUP_ROOT/xr-chaperone/xr-chaperone}"
PSVR2_CHAPERONE_SERVICE_ARGS="${PSVR2_CHAPERONE_SERVICE_ARGS:--s}"
PSVR2_LINK_STABILITY_CHECKS="${PSVR2_LINK_STABILITY_CHECKS:-4}"
PSVR2_LINK_DISCONNECT_CHECKS="${PSVR2_LINK_DISCONNECT_CHECKS:-2}"
PSVR2_LINK_STABILITY_INTERVAL_SECONDS="${PSVR2_LINK_STABILITY_INTERVAL_SECONDS:-1}"
PSVR2_STARTUP_RETRY_BASE_SECONDS="${PSVR2_STARTUP_RETRY_BASE_SECONDS:-12}"
PSVR2_STARTUP_RETRY_MAX_SECONDS="${PSVR2_STARTUP_RETRY_MAX_SECONDS:-120}"
PSVR2_STARTUP_RETRY_ATTEMPTS="${PSVR2_STARTUP_RETRY_ATTEMPTS:-3}"
PSVR2_RUNTIME_FAILURE_STREAK_THRESHOLD="${PSVR2_RUNTIME_FAILURE_STREAK_THRESHOLD:-2}"
PSVR2_RUNTIME_FAILURE_RECOVERY_SECONDS="${PSVR2_RUNTIME_FAILURE_RECOVERY_SECONDS:-90}"
PSVR2_RUNTIME_RETRY_COOLDOWN_SECONDS="${PSVR2_RUNTIME_RETRY_COOLDOWN_SECONDS:-$PSVR2_RUNTIME_FAILURE_RECOVERY_SECONDS}"
PSVR2_TRACKING_LOSS_CHECKS="${PSVR2_TRACKING_LOSS_CHECKS:-3}"
PSVR2_TRACKING_RECOVERY_CHECKS="${PSVR2_TRACKING_RECOVERY_CHECKS:-3}"
PSVR2_TRACKING_RESTART_SECONDS="${PSVR2_TRACKING_RESTART_SECONDS:-60}"
PSVR2_DISCONNECT_CONTROLLERS="${PSVR2_DISCONNECT_CONTROLLERS:-0}"
STEAM_ROOT="${STEAM_ROOT:-$HOME/.local/share/Steam}"
ENVISION_PROFILE_ROOT="${ENVISION_PROFILE_ROOT:-$HOME/.local/share/envision/psvr2-toolkit-monado}"
MONADO_PREFIX="${MONADO_PREFIX:-$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado}"
AMD_VULKAN_DEVICE="${AMD_VULKAN_DEVICE:-}"
DGPU_PCI_ADDRESS="${DGPU_PCI_ADDRESS:-}"
VR_AUDIO_SINK="${VR_AUDIO_SINK:-}"
VR_AUDIO_SOURCE="${VR_AUDIO_SOURCE:-}"
CONTROLLER_LEFT_MAC="${CONTROLLER_LEFT_MAC:-}"
CONTROLLER_RIGHT_MAC="${CONTROLLER_RIGHT_MAC:-}"
STEAM_COMMAND="${STEAM_COMMAND:-steam}"

require_uint() {
    local name=$1 value=$2
    [[ "$value" =~ ^[0-9]+$ ]] || {
        echo "Invalid $name in $config_file: expected a non-negative integer, got '$value'" >&2
        return 1
    }
}

require_bool() {
    local name=$1 value=$2
    [[ "$value" == 0 || "$value" == 1 ]] || {
        echo "Invalid $name in $config_file: expected 0 or 1, got '$value'" >&2
        return 1
    }
}

for setting in PSVR2_RENDER_SCALE PSVR2_LINK_STABILITY_CHECKS \
    PSVR2_LINK_DISCONNECT_CHECKS PSVR2_LINK_STABILITY_INTERVAL_SECONDS \
    PSVR2_STARTUP_RETRY_BASE_SECONDS PSVR2_STARTUP_RETRY_MAX_SECONDS \
    PSVR2_STARTUP_RETRY_ATTEMPTS PSVR2_RUNTIME_FAILURE_STREAK_THRESHOLD \
    PSVR2_RUNTIME_FAILURE_RECOVERY_SECONDS PSVR2_RUNTIME_RETRY_COOLDOWN_SECONDS \
    PSVR2_TRACKING_LOSS_CHECKS PSVR2_TRACKING_RECOVERY_CHECKS \
    PSVR2_TRACKING_RESTART_SECONDS; do
    require_uint "$setting" "${!setting}" || { return 1 2>/dev/null || exit 1; }
done
for setting in PSVR2_SPECTATOR_ENABLE PSVR2_CHAPERONE_ENABLE PSVR2_DISCONNECT_CONTROLLERS; do
    require_bool "$setting" "${!setting}" || { return 1 2>/dev/null || exit 1; }
done
[[ -z "$DGPU_PCI_ADDRESS" || "$DGPU_PCI_ADDRESS" =~ ^0000:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}[.][0-7]$ ]] || {
    echo "Invalid DGPU_PCI_ADDRESS in $config_file: $DGPU_PCI_ADDRESS" >&2
    return 1 2>/dev/null || exit 1
}
[[ "$STEAM_COMMAND" != *[[:space:]]* ]] || {
    echo "STEAM_COMMAND must be one executable path without arguments: $STEAM_COMMAND" >&2
    return 1 2>/dev/null || exit 1
}

export PSVR2_RENDER_SCALE
export PSVR2_SPECTATOR_ENABLE
export PSVR2_CHAPERONE_ENABLE PSVR2_CHAPERONE_BINARY PSVR2_CHAPERONE_SERVICE_ARGS
export PSVR2_LINK_STABILITY_CHECKS PSVR2_LINK_DISCONNECT_CHECKS
export PSVR2_LINK_STABILITY_INTERVAL_SECONDS
export PSVR2_STARTUP_RETRY_BASE_SECONDS PSVR2_STARTUP_RETRY_MAX_SECONDS PSVR2_STARTUP_RETRY_ATTEMPTS
export PSVR2_RUNTIME_FAILURE_STREAK_THRESHOLD PSVR2_RUNTIME_FAILURE_RECOVERY_SECONDS PSVR2_RUNTIME_RETRY_COOLDOWN_SECONDS
export PSVR2_TRACKING_LOSS_CHECKS PSVR2_TRACKING_RECOVERY_CHECKS PSVR2_TRACKING_RESTART_SECONDS
export PSVR2_DISCONNECT_CONTROLLERS
export STEAM_ROOT ENVISION_PROFILE_ROOT
export MONADO_PREFIX PSVR2_SETUP_ROOT AMD_VULKAN_DEVICE DGPU_PCI_ADDRESS

# Sony's bridge can publish orientation and position while its saved play area
# is not actually registered. Only this complete state is safe for STAGE-space
# clients such as games and xr-chaperone. Keep the journal query narrow because
# Monado's renderer log is high-volume.
psvr2_tracking_is_stable() {
    local pid=${1:-} logs last_status last_3dof last_fake last_map last_registration last_playarea
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    local select_latest='head'
    if [[ -n "${PSVR2_TRACKING_LOG_TEXT:-}" ]]; then
        logs=$PSVR2_TRACKING_LOG_TEXT
        select_latest='tail'
    else
        logs=$(journalctl --user -u psvr2-fossvr.service "_PID=$pid" \
            --grep='TrackingStatus|force 3DoF|fake Position|Map (latched|unlatched)|map registration error|\(playarea:' \
            -n 48 -o cat --no-pager 2>/dev/null || true)
    fi
    last_status=$(grep 'TrackingStatus' <<<"$logs" | "$select_latest" -n 1 || true)
    last_3dof=$(grep 'force 3DoF' <<<"$logs" | "$select_latest" -n 1 || true)
    last_fake=$(grep 'fake Position' <<<"$logs" | "$select_latest" -n 1 || true)
    last_map=$(grep -E 'Map (latched|unlatched)' <<<"$logs" | "$select_latest" -n 1 || true)
    last_registration=$(grep 'map registration error' <<<"$logs" | "$select_latest" -n 1 || true)
    last_playarea=$(grep '(playarea:' <<<"$logs" | "$select_latest" -n 1 || true)

    [[ "$last_status" == *'-> stable'* ]] || return 1
    [[ "$last_3dof" == *'force 3DoF OFF'* ]] || return 1
    [[ -z "$last_fake" || "$last_fake" == *'fake Position OFF'* ]] || return 1
    [[ "$last_map" == *'Map latched'* ]] || return 1
    [[ "$last_playarea" == *'(playarea: 1, map latch: 1)'* ]] || return 1
    [[ -z "$last_registration" || "$last_registration" == *'-> 0'* ]] || return 1
}
