#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cycles=${1:-3}

workspace=$(mktemp -d)
cleanup() {
    [[ -n "${monitor_pid:-}" ]] && kill "$monitor_pid" >/dev/null 2>&1 || true
    rm -rf "$workspace"
}
trap cleanup EXIT

helpers="$workspace/helpers"
usb_root="$workspace/usb"
drm_root="$workspace/drm"
connection_state="$workspace/connection-state"
runtime_state="$workspace/runtime-state"
start_log="$workspace/start.log"
stop_log="$workspace/stop.log"
wayvr_log="$workspace/wayvr.log"
start_invocation_log="$workspace/start-invocations.log"
monitor_log="$workspace/monitor.log"

mkdir -p "$helpers" "$usb_root" "$drm_root/card99-DP-1"

cat > "$connection_state" <<EOF2
disconnected
EOF2

printf 'connected' > "$runtime_state"
cat > "$start_log"
cat > "$stop_log"
cat > "$wayvr_log"
cat > "$start_invocation_log"

# Minimal fake PSVR2 USB function + DP sink for headset_connected checks.
mkdir -p "$usb_root/1-1"
printf '054c' > "$usb_root/1-1/idVendor"
printf '0cde' > "$usb_root/1-1/idProduct"
printf '5000' > "$usb_root/1-1/speed"
printf '11' > "$usb_root/1-1/bNumInterfaces"
printf 'connected' > "$drm_root/card99-DP-1/status"
printf 'PS VR2' > "$drm_root/card99-DP-1/edid"

cat > "$helpers/psvr2-fossvr-start" <<'EOF3'
#!/usr/bin/bash
set -u
runtime_state_file=${PSVR2_TEST_RUNTIME_STATE_FILE:-/tmp/psvr2-runtime-state}
count_file=${PSVR2_TEST_START_COUNT_FILE:-/tmp/psvr2-start-count}
invocation_file=${PSVR2_TEST_START_INVOCATION_FILE:-/tmp/psvr2-start-invocations}
wayvr_file=${PSVR2_TEST_WAYVR_START_COUNT_FILE:-/tmp/psvr2-wayvr-start-count}

echo "start" >> "$invocation_file"

echo "start" >> "$count_file"
echo "wayvr" >> "$wayvr_file"
printf 'active\n' > "$runtime_state_file"
exit 0
EOF3
cat > "$helpers/psvr2-fossvr-stop" <<'EOF3'
#!/usr/bin/bash
set -u
runtime_state_file=${PSVR2_TEST_RUNTIME_STATE_FILE:-/tmp/psvr2-runtime-state}
count_file=${PSVR2_TEST_STOP_COUNT_FILE:-/tmp/psvr2-stop-count}
echo "stop" >> "$count_file"
printf 'inactive\n' > "$runtime_state_file"
exit 0
EOF3
cat > "$helpers/psvr2-controller-preflight" <<'EOF3'
#!/usr/bin/bash
exit 0
EOF3
chmod 0755 "$helpers/psvr2-fossvr-start" "$helpers/psvr2-fossvr-stop" "$helpers/psvr2-controller-preflight"

wait_for() {
    local target_file=$1
    local target_count=$2
    local timeout_seconds=$3
    local seen=0

    while (( timeout_seconds-- > 0 )); do
        if [[ -f "$target_file" ]]; then
            seen=$(wc -l < "$target_file")
        else
            seen=0
        fi
        if (( seen >= target_count )); then
            return 0
        fi
        sleep 1
    done
    return 1
}

PSVR2_TEST_MODE=1 \
PSVR2_TEST_RUNTIME_STATE_FILE="$runtime_state" \
PSVR2_TEST_START_COUNT_FILE="$start_log" \
PSVR2_TEST_STOP_COUNT_FILE="$stop_log" \
PSVR2_TEST_START_INVOCATION_FILE="$start_invocation_log" \
PSVR2_TEST_WAYVR_START_COUNT_FILE="$wayvr_log" \
PSVR2_CONNECTION_STATE_FILE="$connection_state" \
PSVR2_USB_ROOT="$usb_root" \
PSVR2_DRM_ROOT="$drm_root" \
PSVR2_HELPER_DIR="$helpers" \
PSVR2_LINK_STABILITY_CHECKS=1 \
PSVR2_LINK_DISCONNECT_CHECKS=1 \
PSVR2_LINK_STABILITY_INTERVAL_SECONDS=1 \
PSVR2_STARTUP_RETRY_ATTEMPTS="${PSVR2_TEST_STARTUP_RETRY_ATTEMPTS:-1}" \
PSVR2_STARTUP_RETRY_BASE_SECONDS="${PSVR2_TEST_STARTUP_RETRY_BASE_SECONDS:-1}" \
PSVR2_STARTUP_RETRY_MAX_SECONDS="${PSVR2_TEST_STARTUP_RETRY_MAX_SECONDS:-2}" \
PSVR2_RUNTIME_RETRY_COOLDOWN_SECONDS=1 \
"$repo/bin/psvr2-autostart-monitor" >"$monitor_log" 2>&1 &
monitor_pid=$!

# Allow monitor to initialize and read the initial disconnected state.
sleep 2

for cycle in $(seq 1 "$cycles"); do
    printf 'connected\n' > "$connection_state"
    start_target=$((cycle))
    if ! wait_for "$start_log" "$start_target" 18; then
        echo "Reconnect cycle $cycle: start did not happen within timeout" >&2
        cat "$monitor_log" >&2
        exit 1
    fi

    printf 'disconnected\n' > "$connection_state"
    stop_target=$((cycle))
    if ! wait_for "$stop_log" "$stop_target" 18; then
        echo "Reconnect cycle $cycle: stop did not happen within timeout" >&2
        cat "$monitor_log" >&2
        exit 1
    fi

done

kill "$monitor_pid" >/dev/null 2>&1 || true
wait "$monitor_pid" 2>/dev/null || true

start_count=$(wc -l < "$start_log")
stop_count=$(wc -l < "$stop_log")
wayvr_count=$(wc -l < "$wayvr_log")

if (( start_count != cycles || stop_count != cycles || wayvr_count != cycles )); then
    echo "Reconnect cycle count mismatch: expected $cycles starts, stops, and wayvr starts, got $start_count/$stop_count/$wayvr_count" >&2
    echo "--- monitor log ---" >&2
    cat "$monitor_log" >&2
    exit 1
fi

invocation_count=$(wc -l < "$start_invocation_log")
if (( invocation_count < cycles )); then
    echo "Reconnect cycle test failed: expected at least $cycles start invocations, got $invocation_count" >&2
    echo "--- monitor log ---" >&2
    cat "$monitor_log" >&2
    exit 1
fi

echo "PSVR2 reconnect cycle test passed: $cycles connect/disconnect cycles with deterministic startup transitions and WayVR init."
echo "Log: $monitor_log"
