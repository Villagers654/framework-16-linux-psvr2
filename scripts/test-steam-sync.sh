#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
workspace=$(mktemp -d)
trap 'rm -rf -- "$workspace"' EXIT
test_home="$workspace/home"
steam="$test_home/Steam"
install -d -m 0755 "$test_home/.config/psvr2-linux" \
  "$steam/steamapps" "$steam/config" "$steam/userdata/1/config"

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

HOME="$test_home" PSVR2_SYNC_RESTART_DASHBOARD=0 \
  python3 "$repo/bin/psvr2-sync-steam-vr-games"

state="$test_home/.local/share/psvr2-setup/steam-vr-apps.json"
jq -e '."341800" == true and ."250820" == false' "$state" >/dev/null
grep -Fq "$test_home/.local/bin/psvr2-fossvr-run %command%" \
  "$steam/userdata/1/config/localconfig.vdf"
grep -Fq '"name"		"proton_experimental"' "$steam/config/config.vdf"
test -f "$steam/userdata/1/config/localconfig.vdf.psvr2-auto-backup"
test -f "$steam/config/config.vdf.psvr2-auto-backup"
echo "Steam metadata sync test passed."
