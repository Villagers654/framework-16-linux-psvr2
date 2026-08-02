#!/usr/bin/bash
set -euo pipefail

echo "Graphics devices:"
lspci -Dnn | grep -Ei 'VGA|3D|Display' || true
echo
echo "Vulkan devices:"
vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|vendorID|deviceID' || true
echo
echo "Connected DRM DisplayPort connectors:"
for status in /sys/class/drm/card*-DP-*/status; do
  [[ -r "$status" ]] && printf '%-55s %s\n' "$status" "$(cat "$status")"
done
echo
echo "PSVR2 USB:"
lsusb -d 054c:0cde || true
