#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
root="$HOME/.local/share/envision/psvr2-toolkit-monado"
config="$HOME/.config/envision/envision.json"
mkdir -p "$root" "$(dirname "$config")"

if [[ ! -d "$root/xrservice/.git" ]]; then
  git clone --branch psvr2-linux-steam-lh https://gitlab.freedesktop.org/Supremium/monado "$root/xrservice"
fi
git -C "$root/xrservice" fetch origin psvr2-linux-steam-lh
git -C "$root/xrservice" checkout 8bd01e7edec8028f65c7bff925195f0454d4bc9f
git -C "$root/xrservice" apply --check "$repo/patches/monado-psvr2-sense.patch" 2>/dev/null && \
  git -C "$root/xrservice" apply "$repo/patches/monado-psvr2-sense.patch" || true
git -C "$root/xrservice" apply --check "$repo/patches/monado-spectator-mirror.patch" 2>/dev/null && \
  git -C "$root/xrservice" apply "$repo/patches/monado-spectator-mirror.patch" || true

if [[ ! -d "$root/xrizer/.git" ]]; then
  git clone --recurse-submodules https://github.com/Supreeeme/xrizer "$root/xrizer"
fi
git -C "$root/xrizer" fetch origin
git -C "$root/xrizer" checkout 6c3e45f4c18b014a7aba87282ee0677306315052
for patch in \
  "$repo/patches/xrizer-linux-room-setup.patch" \
  "$repo/patches/xrizer-linux-room-setup-tracking-guard.patch" \
  "$repo/patches/xrizer-room-setup-proximity.patch"; do
  git -C "$root/xrizer" apply --check "$patch" 2>/dev/null && git -C "$root/xrizer" apply "$patch" || true
done

dri_prime=""
source "$HOME/.config/psvr2-linux/settings.env"
[[ -z "$DGPU_PCI_ADDRESS" ]] || dri_prime="pci-${DGPU_PCI_ADDRESS//:/_}"
dri_prime=${dri_prime//./_}
profile=$(mktemp)
sed -e "s|@HOME@|$HOME|g" -e "s|@DRI_PRIME@|$dri_prime|g" "$repo/config/envision-profile.json.in" > "$profile"

if [[ -f "$config" ]]; then cp -n "$config" "$config.before-psvr2" || true; else echo '{"user_profiles":[]}' > "$config"; fi
tmp=$(mktemp)
jq --slurpfile profile "$profile" '
  .user_profiles = ((.user_profiles // []) | map(select(.uuid != "psvr2-toolkit-monado")) + [$profile[0]]) |
  .selected_profile_uuid = "psvr2-toolkit-monado" |
  .profiles_enabled = true
' "$config" > "$tmp"
mv "$tmp" "$config"
rm -f "$profile"

echo "Envision profile installed. Open Envision, select the PSVR2 profile, and Clean Build."
echo "The profile is pinned and pull-on-build is disabled so these patches persist."
