#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
work_dir=$(mktemp -d)
trap 'find "$work_dir" -depth -delete' EXIT

mapfile -t shell_files < <(
  find bin scripts lib systemd/system -type f -print0 \
    | xargs -0 awk 'FNR == 1 && /\/usr\/bin\/(env )?(ba)?sh/ { print FILENAME }' \
    | sort -u
)

for file in "${shell_files[@]}" install.sh; do
  bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S warning install.sh "${shell_files[@]}"
else
  echo "WARN shellcheck is not installed; skipping shell static analysis" >&2
fi

pycache="$work_dir/pycache"
mkdir -p "$pycache"
PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile bin/psvr2-sync-steam-vr-games
PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile bin/psvr2-launch-registered-vr
python3 -m json.tool config/room-setup-bindings-oculus-touch.json >/dev/null
python3 -m json.tool config/envision-profile.json.in >/dev/null
grep -Fq 'PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1' \
  config/environment.d/60-psvr2-openxr.conf.in
grep -Fq 'psvr2-sync-steam-vr-games --discovery-only' \
  systemd/user/psvr2-steam-vr-sync.service
grep -Fq '\[HMD\] Track at p:.*\(st: 2 1 4\)' bin/psvr2-room-setup
grep -Fq '\[HMD\] (Jump|Lost)' bin/psvr2-room-setup
grep -Fq 'systemctl --user stop psvr2-chaperone.service' bin/psvr2-room-setup
grep -Fq 'required after *every*' bin/psvr2-room-setup
grep -Fq 'while kill -0 -- "-$game_pid"' bin/psvr2-fossvr-run
grep -Fq 'game_registration="$game_registry_dir/$BASHPID"' bin/psvr2-fossvr-run
grep -Fq 'game_stop_helper="$helper_dir/psvr2-stop-games"' bin/psvr2-fossvr-stop
bash -n bin/psvr2-stop-games
bin/psvr2-import-boundary tests/fixtures/psvr2-chaperone.vrchap \
  "$work_dir/chaperone.toml"
test "$(grep -c '^\[\[boundary\]\]$' "$work_dir/chaperone.toml")" = 4
python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
  "$work_dir/chaperone.toml"
bin/psvr2-import-boundary tests/fixtures/psvr2-chaperone-offset.vrchap \
  "$work_dir/chaperone-offset.toml"
python3 - "$work_dir/chaperone-offset.toml" <<'PY'
import math
import sys
import tomllib

with open(sys.argv[1], "rb") as stream:
    points = tomllib.load(stream)["boundary"]
xs = [point["x"] for point in points]
zs = [point["z"] for point in points]
assert math.isclose(min(xs), -1.0, abs_tol=1e-6)
assert math.isclose(max(xs), 1.0, abs_tol=1e-6)
assert math.isclose(min(zs), -1.0, abs_tol=1e-6)
assert math.isclose(max(zs), 1.0, abs_tol=1e-6)
# The standing transform belongs to device poses; the collision polygon is
# already in STAGE coordinates and remains centered on (0, 0).
inside = False
for first, second in zip(points, points[1:] + points[:1]):
    if ((first["z"] > 0.0) != (second["z"] > 0.0)) and \
       (0.0 < (second["x"] - first["x"]) * (0.0 - first["z"]) /
               (second["z"] - first["z"]) + first["x"]):
        inside = not inside
assert inside
PY
for patch in patches/*.patch; do
  git apply --stat "$patch" >/dev/null
done

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify systemd/user/*
  verify_root="$work_dir/systemd-root"
  install -Dm0755 systemd/system/psvr2-dgpu-power \
    "$verify_root/usr/local/libexec/psvr2-dgpu-power"
  install -Dm0644 systemd/system/psvr2-dgpu-power.service \
    "$verify_root/etc/systemd/system/psvr2-dgpu-power.service"
  sed -i 's/@DGPU_PCI_ADDRESS@/0000:03:00.0/g' \
    "$verify_root/etc/systemd/system/psvr2-dgpu-power.service"
  install -Dm0755 systemd/system/psvr2-usb-recover \
    "$verify_root/usr/local/libexec/psvr2-usb-recover"
  install -Dm0644 systemd/system/psvr2-usb-recover.service \
    "$verify_root/etc/systemd/system/psvr2-usb-recover.service"
  for unit in sysinit.target basic.target shutdown.target; do
    install -Dm0644 "/usr/lib/systemd/system/$unit" \
      "$verify_root/usr/lib/systemd/system/$unit"
  done
  systemd-analyze verify --root="$verify_root" psvr2-dgpu-power.service psvr2-usb-recover.service
fi

./scripts/verify-reconnect-cycle.sh
./scripts/test-steam-sync.sh
./scripts/test-stop-games.sh
echo "Repository checks passed."
