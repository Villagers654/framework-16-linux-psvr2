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

monado_patches=(
  "$repo/patches/monado-prefer-psvr2-toolkit.patch"
  "$repo/patches/monado-runtime-compat.patch"
  "$repo/patches/monado-steamvr-hmd-tracking.patch"
  "$repo/patches/monado-psvr2-sense.patch"
  "$repo/patches/monado-steamvr-touch-bindings.patch"
  "$repo/patches/monado-steamvr-host-poses.patch"
  "$repo/patches/monado-openvr-controller-tracking.patch"
  "$repo/patches/monado-ipc-input-filter.patch"
  "$repo/patches/monado-psvr2-usb-recovery.patch"
  "$repo/patches/monado-spectator-mirror.patch"
  "$repo/patches/monado-stage-bounds.patch"
)
unapply_managed_patches() {
  local tree=$1
  shift
  local patches=("$@") patch index
  for ((index=${#patches[@]} - 1; index >= 0; index--)); do
    patch=${patches[index]}
    if git -C "$tree" apply --reverse --check "$patch" 2>/dev/null; then
      git -C "$tree" apply --reverse "$patch"
    fi
  done
  if ! git -C "$tree" diff --quiet || ! git -C "$tree" diff --cached --quiet; then
    echo "Refusing to overwrite unmanaged changes in $tree" >&2
    exit 1
  fi
}

if [[ ! -d "$root/xrservice/.git" ]]; then
  git clone --branch psvr2-linux-steam-lh https://gitlab.freedesktop.org/Supremium/monado "$root/xrservice"
fi
unapply_managed_patches "$root/xrservice" "${monado_patches[@]}"
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
for patch in "${monado_patches[@]}"; do
  apply_patch_once "$root/xrservice" "$patch"
done
git -C "$root/xrservice" diff --check

riftlift_source="$root/riftlift"
if [[ ! -d "$riftlift_source/.git" ]]; then
  git clone --recurse-submodules https://github.com/Villagers654/RiftLift "$riftlift_source"
fi
if ! git -C "$riftlift_source" diff --quiet || ! git -C "$riftlift_source" diff --cached --quiet; then
  echo "Refusing to overwrite unmanaged changes in $riftlift_source" >&2
  exit 1
fi
git -C "$riftlift_source" remote set-url origin https://github.com/Villagers654/RiftLift
git -C "$riftlift_source" fetch origin main
git -C "$riftlift_source" checkout --detach 0f843fd94aa6507cd53f440fa099dfc1f1ab2bcd
git -C "$riftlift_source" submodule update --init --recursive
git -C "$riftlift_source" diff --check
[[ -f "$riftlift_source/components/xrizer/Cargo.toml" ]] || {
  echo "RiftLift's xrizer component is missing." >&2
  exit 1
}

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

echo "Envision profile installed. Run ./scripts/build-envision-runtime.sh to build it."
echo "The profile is pinned and pull-on-build is disabled so the tested sources persist."
