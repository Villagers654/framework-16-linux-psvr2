#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
workspace=$(mktemp -d)
trap 'find "$workspace" -depth -delete' EXIT
test_home="$workspace/home"
steam="$test_home/Steam"
install -d -m 0755 "$test_home/.config/psvr2-linux" \
  "$test_home/.local/bin" "$steam/steamapps" "$steam/config" "$steam/userdata/1/config"
install -m 0755 /dev/null "$test_home/.local/bin/psvr2-fossvr-run"
cat > "$test_home/.local/bin/riftlift" <<'EOF'
#!/usr/bin/bash
if [[ ${1:-} == steam-oculus-ids ]]; then
  echo 1920760
fi
EOF
chmod 0755 "$test_home/.local/bin/riftlift"

cat > "$test_home/.config/psvr2-linux/settings.env" <<EOF
STEAM_ROOT="$steam"
PSVR2_MANAGE_STEAM_LAUNCH_OPTIONS=1
EOF
chmod 0600 "$test_home/.config/psvr2-linux/settings.env"

cat > "$steam/steamapps/appmanifest_341800.acf" <<'EOF'
"AppState"
{
	"appid"		"341800"
	"name"		"Keep Talking and Nobody Explodes"
	"StateFlags"		"4"
	"installdir"		"Keep Talking and Nobody Explodes"
}
EOF
cat > "$steam/steamapps/appmanifest_250820.acf" <<'EOF'
"AppState"
{
	"appid"		"250820"
	"name"		"SteamVR"
	"StateFlags"		"4"
	"installdir"		"SteamVR"
}
EOF
cat > "$steam/steamapps/appmanifest_1920760.acf" <<'EOF'
"AppState"
{
	"appid"		"1920760"
	"name"		"StereoPaint"
	"StateFlags"		"4"
	"installdir"		"StereoPaint"
}
EOF
cat > "$steam/userdata/1/config/localconfig.vdf" <<'EOF'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"341800"
					{
					}
					"1920760"
					{
					}
				}
			}
		}
	}
}
EOF
cat > "$steam/config/config.vdf" <<'EOF'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
				}
			}
		}
	}
}
EOF

local_vr_launcher="$test_home/Vader Immortal.sh"
install -m 0755 /dev/null "$local_vr_launcher"
cat > "$steam/config/steamapps.vrmanifest" <<EOF
{
  "applications": [
    {
      "app_key": "steam.app.2600304528",
      "launch_type": "binary",
      "strings": {"en_us": {"name": "Vader Immortal: Episode I"}},
      "binary_path_linux": "$local_vr_launcher"
    }
  ]
}
EOF

HOME="$test_home" PSVR2_SYNC_RESTART_DASHBOARD=0 \
  python3 "$repo/bin/psvr2-sync-steam-vr-games" --force

state="$test_home/.local/share/psvr2-setup/steam-vr-apps.json"
jq -e '."341800" == true and ."1920760" == true and ."250820" == false and ."2600304528" == true' "$state" >/dev/null
expected_command="$test_home/.local/bin/psvr2-fossvr-run '$local_vr_launcher'"
test "$(HOME="$test_home" python3 "$repo/bin/psvr2-launch-registered-vr" --check 2600304528)" = \
  "$expected_command"
grep -Fq "$test_home/.local/bin/psvr2-fossvr-run %command%" \
  "$steam/userdata/1/config/localconfig.vdf"
grep -Fq "$test_home/.local/bin/psvr2-fossvr-run $test_home/.local/bin/riftlift launch-steam 1920760 -- %command%" \
  "$steam/userdata/1/config/localconfig.vdf"
grep -Fq '"name"		"proton_experimental"' "$steam/config/config.vdf"
test -f "$steam/userdata/1/config/localconfig.vdf.psvr2-auto-backup"
test -f "$steam/config/config.vdf.psvr2-auto-backup"
state_mtime=$(stat -c '%Y' "$state")
sleep 1
HOME="$test_home" PSVR2_SYNC_RESTART_DASHBOARD=0 \
  python3 "$repo/bin/psvr2-sync-steam-vr-games" --discovery-only
test "$(stat -c '%Y' "$state")" = "$state_mtime"

# A metadata refresh must never restart WayVR over a running title. The shared
# launch marker is the authoritative lifecycle state for Steam and Rift games.
XDG_RUNTIME_DIR="$workspace/runtime" REPO="$repo" python3 - <<'PY'
import importlib.machinery
import os
from pathlib import Path
from types import SimpleNamespace

runtime = Path(os.environ["XDG_RUNTIME_DIR"])
runtime.mkdir()
loader = importlib.machinery.SourceFileLoader(
    "steam_sync", str(Path(os.environ["REPO"]) / "bin/psvr2-sync-steam-vr-games")
)
steam_sync = loader.load_module()
calls = []

def fake_run(command, **_kwargs):
    calls.append(command)
    return SimpleNamespace(returncode=0, stdout="", stderr="")

steam_sync.subprocess.run = fake_run
steam_sync.GAME_REGISTRY.mkdir()
(steam_sync.GAME_REGISTRY / "launch").touch()
steam_sync.restart_wayvr_dashboard()
assert calls == [], calls
(steam_sync.GAME_REGISTRY / "launch").unlink()
steam_sync.restart_wayvr_dashboard()
assert calls[-1] == [
    "systemctl", "--user", "restart", "psvr2-fossvr-wayvr.service"
], calls
PY
echo "Steam metadata sync test passed."
