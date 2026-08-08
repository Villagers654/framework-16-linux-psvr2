#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

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

pycache=$(mktemp -d)
PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile bin/psvr2-sync-steam-vr-games
python3 -m json.tool config/room-setup-bindings-oculus-touch.json >/dev/null
python3 -m json.tool config/envision-profile.json.in >/dev/null
for patch in patches/*.patch; do
  git apply --stat "$patch" >/dev/null
done

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify systemd/user/* systemd/system/psvr2-dgpu-power.service
fi

./scripts/verify-reconnect-cycle.sh
./scripts/test-steam-sync.sh
echo "Repository checks passed."
