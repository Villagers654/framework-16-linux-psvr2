#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'find "$test_root" -depth -delete' EXIT

mkdir -p "$test_root/cgroup/test.scope" "$test_root/bin"
printf '4242\n4243\n' > "$test_root/cgroup/test.scope/cgroup.procs"

cat > "$test_root/bin/systemctl" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == *"ControlGroup"* ]]; then
    printf '/test.scope\n'
    exit 0
fi
exit 0
EOF

cat > "$test_root/bin/pactl" <<'EOF'
#!/usr/bin/bash
if [[ "$*" == "-f json list sinks" ]]; then
    printf '%s\n' '[{"index":42,"name":"headset-sink"}]'
    exit 0
fi
if [[ "$*" == "-f json list sink-inputs" ]]; then
    printf '%s\n' '[{"index":7,"sink":3,"mute":true,"properties":{"application.process.id":"4242"}},{"index":8,"sink":3,"mute":true,"properties":{"application.process.id":"9999"}},{"index":9,"sink":42,"mute":false,"properties":{"application.process.id":"4243"}}]'
    exit 0
fi
printf '%s\n' "$*" >> "$PSVR2_PACTL_LOG"
EOF
chmod 0755 "$test_root/bin/systemctl" "$test_root/bin/pactl"

PSVR2_SYSTEMCTL_BIN="$test_root/bin/systemctl" \
PSVR2_PACTL_BIN="$test_root/bin/pactl" \
PSVR2_PACTL_LOG="$test_root/pactl.log" \
PSVR2_CGROUP_ROOT="$test_root/cgroup" \
PSVR2_AUDIO_GUARD_ONCE=1 \
    "$repo/bin/psvr2-game-audio-guard" psvr2-game-test.scope headset-sink

grep -Fxq 'move-sink-input 7 headset-sink' "$test_root/pactl.log"
grep -Fxq 'set-sink-input-mute 7 0' "$test_root/pactl.log"
grep -Fxq 'set-sink-input-volume 7 100%' "$test_root/pactl.log"
! grep -Fq ' 8 ' "$test_root/pactl.log"
grep -Fxq 'set-sink-input-volume 9 100%' "$test_root/pactl.log"
! grep -Fq 'move-sink-input 9 ' "$test_root/pactl.log"
! grep -Fq 'set-sink-input-mute 9 ' "$test_root/pactl.log"

echo 'PSVR2 game audio guardian test passed.'
