#!/usr/bin/bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/psvr2-common.sh
source "$repo/lib/psvr2-common.sh"
for command in git jq mktemp sed; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done
root="$ENVISION_PROFILE_ROOT"
config="${XDG_CONFIG_HOME:-$HOME/.config}/envision/envision.json"
mkdir -p "$root" "$(dirname "$config")"

if [[ ! -d "$root/xrservice/.git" ]]; then
  git clone --branch psvr2-linux-steam-lh https://gitlab.freedesktop.org/Supremium/monado "$root/xrservice"
fi
git -C "$root/xrservice" fetch origin psvr2-linux-steam-lh
git -C "$root/xrservice" checkout --detach 8bd01e7edec8028f65c7bff925195f0454d4bc9f
apply_patch_once() {
  local tree=$1 patch=$2
  if git -C "$tree" apply --check "$patch"; then
    git -C "$tree" apply "$patch"
  elif git -C "$tree" apply --reverse --check "$patch"; then
    echo "Already applied: $(basename "$patch")"
  else
    echo "Patch does not apply cleanly: $patch" >&2
    exit 1
  fi
}
apply_patch_once "$root/xrservice" "$repo/patches/monado-psvr2-sense.patch"
apply_patch_once "$root/xrservice" "$repo/patches/monado-psvr2-usb-recovery.patch"
apply_patch_once "$root/xrservice" "$repo/patches/monado-spectator-mirror.patch"
git -C "$root/xrservice" diff --check

if [[ ! -d "$root/xrizer/.git" ]]; then
  git clone --recurse-submodules https://github.com/Supreeeme/xrizer "$root/xrizer"
fi
git -C "$root/xrizer" fetch origin
git -C "$root/xrizer" checkout --detach 6c3e45f4c18b014a7aba87282ee0677306315052
git -C "$root/xrizer" submodule update --init --recursive
for patch in \
  "$repo/patches/xrizer-linux-room-setup.patch" \
  "$repo/patches/xrizer-chaperone-bounds.patch" \
  "$repo/patches/xrizer-linux-room-setup-tracking-guard.patch" \
  "$repo/patches/xrizer-room-setup-proximity.patch"; do
  apply_patch_once "$root/xrizer" "$patch"
done
git -C "$root/xrizer" diff --check

dri_prime=""
[[ -z "$DGPU_PCI_ADDRESS" ]] || dri_prime="pci-${DGPU_PCI_ADDRESS//:/_}"
dri_prime=${dri_prime//./_}
profile=$(mktemp)
escaped_home=${HOME//\\/\\\\}; escaped_home=${escaped_home//&/\\&}; escaped_home=${escaped_home//|/\\|}
escaped_dri=${dri_prime//\\/\\\\}; escaped_dri=${escaped_dri//&/\\&}; escaped_dri=${escaped_dri//|/\\|}
sed -e "s|@HOME@|$escaped_home|g" -e "s|@DRI_PRIME@|$escaped_dri|g" \
  "$repo/config/envision-profile.json.in" > "$profile"

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
