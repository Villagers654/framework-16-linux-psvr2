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
PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile scripts/patch-revive-openxr.py
PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile scripts/patch-revive-openvr.py
python3 -m json.tool config/room-setup-bindings-oculus-touch.json >/dev/null
python3 -m json.tool config/envision-profile.json.in >/dev/null
grep -Fq 'PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1' \
  config/environment.d/60-psvr2-openxr.conf.in
grep -Fq 'psvr2-sync-steam-vr-games --discovery-only' \
  systemd/user/psvr2-steam-vr-sync.service
bin/psvr2-import-boundary tests/fixtures/psvr2-chaperone.vrchap \
  "$work_dir/chaperone.toml"
test "$(grep -c '^\[\[boundary\]\]$' "$work_dir/chaperone.toml")" = 4
python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
  "$work_dir/chaperone.toml"
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
echo "Repository checks passed."
