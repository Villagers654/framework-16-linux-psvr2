#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
cleanup() {
    [[ -z "${holder_pid:-}" ]] || kill -KILL -- "-$holder_pid" 2>/dev/null || true
    rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p "$test_root/bin" "$test_root/helpers" "$test_root/runtime"
lock="$test_root/runtime/psvr2-fossvr-start.lock"
touch "$test_root/runtime/wayvr.pid" \
    "$test_root/runtime/wayvr.disp" \
    "$test_root/runtime/monado_comp_ipc"

# Model Room Setup holding the lifecycle lock through its nested start helper.
setsid flock "$lock" sleep 30 &
holder_pid=$!
for _ in $(seq 1 20); do
    flock -n "$lock" true 2>/dev/null || break
    sleep 0.05
done

cat > "$test_root/bin/systemctl" <<'EOF'
#!/usr/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$PSVR2_TEST_SYSTEMCTL_LOG"
if [[ "$*" == *"stop psvr2-room-setup.service"* ]]; then
    kill -TERM -- "-$PSVR2_TEST_ROOM_SETUP_PGID" 2>/dev/null || true
elif [[ "$*" == *"show psvr2-fossvr.service"* ]]; then
    printf 'inactive\n'
fi
exit 0
EOF
chmod 0755 "$test_root/bin/systemctl"

for helper in psvr2-stop-games psvr2-runtime-preflight psvr2-audio; do
    cat > "$test_root/helpers/$helper" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
    chmod 0755 "$test_root/helpers/$helper"
done

output=$(PATH="$test_root/bin:$PATH" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    PSVR2_HELPER_DIR="$test_root/helpers" \
    PSVR2_AUTOMATED_STOP=1 \
    PSVR2_STOP_LOCK_TIMEOUT_SECONDS=1 \
    PSVR2_TEST_ROOM_SETUP_PGID="$holder_pid" \
    PSVR2_TEST_SYSTEMCTL_LOG="$test_root/systemctl.log" \
    timeout 5 "$repo/bin/psvr2-fossvr-stop")

grep -Fq 'PSVR2 runtime stopped.' <<<"$output"
grep -Fxq -- '--no-ask-password --no-block stop psvr2-dgpu-power.service' \
    "$test_root/systemctl.log"
for artifact in wayvr.pid wayvr.disp monado_comp_ipc; do
    if [[ -e "$test_root/runtime/$artifact" || -S "$test_root/runtime/$artifact" ]]; then
        echo "Disconnect teardown left stale runtime artifact: $artifact" >&2
        exit 1
    fi
done
if kill -0 "$holder_pid" 2>/dev/null; then
    echo "Disconnect teardown remained blocked behind Room Setup" >&2
    exit 1
fi

echo "PSVR2 disconnect stop preemption test passed."
