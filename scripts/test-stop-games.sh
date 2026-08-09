#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
cleanup() {
    [[ -z "${wrapper_pid:-}" ]] || kill -KILL "$wrapper_pid" 2>/dev/null || true
    [[ -z "${unrelated_pid:-}" ]] || kill -KILL "$unrelated_pid" 2>/dev/null || true
    rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p "$test_root/runtime"
cp "$repo/bin/psvr2-fossvr-run" "$test_root/psvr2-fossvr-run"

# This small legacy-style wrapper proves the compatibility scan is exact and
# that the helper kills its complete process group rather than all Wine/shell
# processes. It intentionally has no new registry entry.
cat > "$test_root/legacy-body" <<'EOF'
#!/usr/bin/bash
trap 'kill -TERM -- "-$child" 2>/dev/null || true; exit 0' TERM
setsid sleep 300 &
child=$!
while kill -0 -- "-$child" 2>/dev/null; do sleep 0.1; done
EOF
chmod 0755 "$test_root/legacy-body"
cp "$test_root/legacy-body" "$test_root/psvr2-fossvr-run"

"$test_root/psvr2-fossvr-run" &
wrapper_pid=$!
sleep 300 &
unrelated_pid=$!
sleep 0.2

XDG_RUNTIME_DIR="$test_root/runtime" \
    PSVR2_GAME_REGISTRY_DIR="$test_root/runtime/psvr2-games" \
    PSVR2_LEGACY_WRAPPER_PIDS="$wrapper_pid" \
    PSVR2_GAME_STOP_WAIT_STEPS=20 \
    "$repo/bin/psvr2-stop-games"

if kill -0 "$wrapper_pid" 2>/dev/null; then
    echo "VR launch wrapper survived stop" >&2
    exit 1
fi
if ! kill -0 "$unrelated_pid" 2>/dev/null; then
    echo "unrelated process was stopped" >&2
    exit 1
fi

echo "PSVR2 game stop test passed."
