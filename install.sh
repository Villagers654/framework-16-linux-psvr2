#!/usr/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=""
framework=false
purge_data=false

usage() {
    cat <<'EOF'
Usage:
  ./install.sh --user [--framework16-rx7700s]
  sudo ./install.sh --system [--framework16-rx7700s]
  ./install.sh --uninstall-user [--purge-data]
  sudo ./install.sh --uninstall-system

--user installs launchers, scripts, settings, and user services.
--system installs PSVR2 udev permissions and optional AMD/Framework services.
--purge-data also removes generated sources, builds, and PSVR2 configuration.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --user|--system|--uninstall-user|--uninstall-system)
            [[ -z "$mode" ]] || { echo "Choose exactly one install mode." >&2; exit 2; }
            mode=${arg#--}
            ;;
        --framework16-rx7700s) framework=true ;;
        --purge-data) purge_data=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n "$mode" ]] || { usage >&2; exit 2; }

user_units=(
    psvr2-autostart-monitor.service
    psvr2-chaperone.service
    psvr2-fossvr-wayvr.service
    psvr2-fossvr.service
    psvr2-room-setup.service
    psvr2-steam-vr-sync.path
    psvr2-steam-vr-sync.service
    psvr2-steam-vr-sync.timer
)
legacy_units=(
    psvr2-steamvr-bridge.path
    psvr2-steamvr-bridge.service
    psvr2-steamvr-maintenance.path
    psvr2-steamvr-maintenance.service
)
legacy_helpers=(
    psvr2-compositor-preflight
    psvr2-controller-preflight
    psvr2-dashboard-mode
    psvr2-register-steam-library
    psvr2-steamvr-bridge
    steamvr-room-setup-on-fedora
    psvr2-spectator
    psvr2-chaperone-sanity
)
legacy_desktops=(
    SteamVR.desktop
    psvr2-fossvr.desktop
    psvr2-fossvr-stop.desktop
    valve-steamvr.desktop
    psvr2-spectator-toggle.desktop
)

uninstall_user() {
    [[ ${EUID} -ne 0 ]] || { echo "Run --uninstall-user as your normal account." >&2; exit 1; }
    systemctl --user disable --now psvr2-autostart-monitor.service \
        psvr2-steam-vr-sync.path psvr2-steam-vr-sync.timer \
        "${legacy_units[@]}" 2>/dev/null || true
    systemctl --user stop psvr2-fossvr-wayvr.service psvr2-chaperone.service \
        psvr2-fossvr.service 2>/dev/null || true

    local file
    for file in "$repo_dir"/bin/*; do
        rm -f -- "$HOME/.local/bin/$(basename "$file")"
    done
    for file in "${legacy_helpers[@]}"; do
        rm -f -- "$HOME/.local/bin/$file"
    done
    for file in "${user_units[@]}" "${legacy_units[@]}"; do
        rm -f -- "$HOME/.config/systemd/user/$file"
    done
    for file in "$repo_dir"/desktop/*.desktop.in; do
        rm -f -- "$HOME/.local/share/applications/$(basename "${file%.in}")"
    done
    for file in "${legacy_desktops[@]}"; do
        rm -f -- "$HOME/.local/share/applications/$file"
    done
    rm -f -- "$HOME/.local/lib/psvr2-linux/common.sh" \
        "$HOME/.config/environment.d/60-psvr2-openxr.conf" \
        "$HOME/.config/wireplumber/wireplumber.conf.d/51-psvr2-displayport-audio.conf"
    rm -f -- "$HOME/.config/systemd/user/psvr2-fossvr.service.d/50-spectator.conf"

    if $purge_data; then
        rm -rf -- "$HOME/.config/psvr2-linux" "$HOME/.config/monado/psvr2" \
            "$HOME/.config/wayvr" "$HOME/.config/xr-chaperone" \
            "$HOME/.local/share/psvr2-setup" \
            "$HOME/.local/share/envision/psvr2-toolkit-monado" \
            "$HOME/.local/share/envision/prefixes/psvr2-toolkit-monado" \
            "$HOME/.local/state/xrizer" \
            "$HOME/.local/state/foveabridge-steamvr-headless" \
            "$HOME/.local/lib/psvr2-kmsgrab" \
            "$HOME/.local/lib64/steamvr-room-setup-on-fedora" \
            "$HOME/.local/src/steamvr-room-setup-on-fedora" \
            "$HOME/.cache/SteamVR" "$HOME/.cache/wayvr" "$HOME/.cache/envision"
    fi
    systemctl --user daemon-reload
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    echo "PSVR2 user integration removed$($purge_data && printf ' with generated data')."
}

uninstall_system() {
    [[ ${EUID} -eq 0 ]] || { echo "Run --uninstall-system with sudo." >&2; exit 1; }
    systemctl disable --now psvr2-dgpu-power.service 2>/dev/null || true
    rm -f -- /etc/udev/rules.d/70-psvr2.rules \
        /etc/udev/rules.d/70-psvr2-dgpu-power.rules \
        /etc/udev/rules.d/71-psvr2-dgpu-power.rules \
        /etc/udev/rules.d/71-psvr2-gpu-profile.rules \
        /etc/systemd/system/psvr2-dgpu-power.service \
        /etc/systemd/system/psvr2-usb-recover.service \
        /etc/polkit-1/rules.d/49-psvr2-usb-recover.rules \
        /usr/local/libexec/psvr2-dgpu-power \
        /usr/local/libexec/psvr2-usb-recover
    systemctl daemon-reload
    udevadm control --reload-rules
    echo "PSVR2 system integration removed."
}

case "$mode" in
    uninstall-user) uninstall_user; exit 0 ;;
    uninstall-system) uninstall_system; exit 0 ;;
esac

if $purge_data; then
    echo "--purge-data is only valid with --uninstall-user." >&2
    exit 2
fi

if [[ "$mode" == user ]]; then
    [[ ${EUID} -ne 0 ]] || { echo "Run --user as your normal account." >&2; exit 1; }
    install -d -m 0755 "$HOME/.local/bin" "$HOME/.local/lib/psvr2-linux" \
        "$HOME/.config/psvr2-linux" "$HOME/.config/systemd/user" \
        "$HOME/.config/environment.d" \
        "$HOME/.config/wireplumber/wireplumber.conf.d" \
        "$HOME/.local/share/applications" "$HOME/.local/share/psvr2-setup"
    while IFS= read -r -d '' script; do
        install -m 0755 "$script" "$HOME/.local/bin/"
    done < <(find "$repo_dir/bin" -maxdepth 1 -type f -print0)
    install -m 0644 "$repo_dir/lib/psvr2-common.sh" "$HOME/.local/lib/psvr2-linux/common.sh"
    rm -f -- "${legacy_units[@]/#/$HOME/.config/systemd/user/}"
    rm -f -- "${legacy_helpers[@]/#/$HOME/.local/bin/}"
    rm -f -- "${legacy_desktops[@]/#/$HOME/.local/share/applications/}"
    rm -f -- "$HOME/.config/systemd/user/psvr2-fossvr.service.d/50-spectator.conf"
    install -m 0644 "$repo_dir"/systemd/user/* "$HOME/.config/systemd/user/"

    if [[ ! -e "$HOME/.config/psvr2-linux/settings.env" ]]; then
        install -m 0600 "$repo_dir/config/settings.env.example" \
            "$HOME/.config/psvr2-linux/settings.env"
        if ! command -v bazzite-steam >/dev/null 2>&1; then
            sed -i 's|STEAM_COMMAND="/usr/bin/bazzite-steam"|STEAM_COMMAND="steam"|' \
                "$HOME/.config/psvr2-linux/settings.env"
        fi
        if ! $framework; then
            sed -i 's/^AMD_VULKAN_DEVICE=.*/AMD_VULKAN_DEVICE=""/' \
                "$HOME/.config/psvr2-linux/settings.env"
            sed -i 's/^DGPU_PCI_ADDRESS=.*/DGPU_PCI_ADDRESS=""/' \
                "$HOME/.config/psvr2-linux/settings.env"
            sed -i 's/^VR_AUDIO_SINK=.*/VR_AUDIO_SINK=""/' \
                "$HOME/.config/psvr2-linux/settings.env"
        fi
    fi
    sed -i -e '/^PSVR2_SPECTATOR_ENABLE=/d' \
        -e '/^PSVR2_LOAD_PSVR2_SENSE=/d' \
        -e '/^PSVR2_REFRESH_RATE=/d' \
        -e '/^PSVR2_USB_RECOVERY_COOLDOWN_SECONDS=/d' \
        "$HOME/.config/psvr2-linux/settings.env"
    chmod 0600 "$HOME/.config/psvr2-linux/settings.env"

    # Apply LVRA's DisplayPort dropout fix only to the configured HMD sink.
    # shellcheck disable=SC1090
    source "$HOME/.config/psvr2-linux/settings.env"
    sed -e "s|@MONADO_PREFIX@|$MONADO_PREFIX|g" \
        -e "s|@ENVISION_PROFILE_ROOT@|$ENVISION_PROFILE_ROOT|g" \
        "$repo_dir/config/environment.d/60-psvr2-openxr.conf.in" \
        > "$HOME/.config/environment.d/60-psvr2-openxr.conf"
    chmod 0644 "$HOME/.config/environment.d/60-psvr2-openxr.conf"
    audio_rule="$HOME/.config/wireplumber/wireplumber.conf.d/51-psvr2-displayport-audio.conf"
    if [[ -n "${VR_AUDIO_SINK:-}" ]]; then
        [[ "$VR_AUDIO_SINK" =~ ^[A-Za-z0-9_.:-]+$ ]] || {
            echo "VR_AUDIO_SINK contains unsupported characters: $VR_AUDIO_SINK" >&2
            exit 1
        }
        sed "s|@VR_AUDIO_SINK@|$VR_AUDIO_SINK|g" \
            "$repo_dir/config/wireplumber/51-psvr2-displayport-audio.conf.in" > "$audio_rule"
        chmod 0644 "$audio_rule"
    else
        rm -f "$audio_rule"
    fi

    for template in "$repo_dir"/desktop/*.desktop.in; do
        target="$HOME/.local/share/applications/$(basename "${template%.in}")"
        sed "s|@HOME@|$HOME|g" "$template" > "$target"
        chmod 0644 "$target"
    done

    systemctl --user daemon-reload
    systemctl --user disable --now "${legacy_units[@]}" 2>/dev/null || true
    systemctl --user enable psvr2-autostart-monitor.service \
        psvr2-steam-vr-sync.path psvr2-steam-vr-sync.timer
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    echo "User integration installed. Review ~/.config/psvr2-linux/settings.env."
    exit 0
fi

[[ ${EUID} -eq 0 ]] || { echo "Run --system with sudo." >&2; exit 1; }
install -m 0644 "$repo_dir/udev/70-psvr2.rules" /etc/udev/rules.d/70-psvr2.rules
install -d -m 0755 /usr/local/libexec
rm -f -- /etc/systemd/system/psvr2-usb-recover.service \
    /etc/polkit-1/rules.d/49-psvr2-usb-recover.rules \
    /usr/local/libexec/psvr2-usb-recover
if $framework; then
    mapfile -t dgpus < <(lspci -Dn | awk '$3 == "1002:7480" {
        address=$1
        sub(/:$/, "", address)
        if (address !~ /^[[:xdigit:]]{4}:/) address="0000:" address
        print address
    }')
    [[ ${#dgpus[@]} -eq 1 ]] || {
        echo "Expected exactly one Framework RX 7700S (1002:7480), found ${#dgpus[@]}." >&2
        exit 1
    }
    install -m 0755 "$repo_dir/systemd/system/psvr2-dgpu-power" /usr/local/libexec/
    sed "s|@DGPU_PCI_ADDRESS@|${dgpus[0]}|g" \
        "$repo_dir/systemd/system/psvr2-dgpu-power.service" \
        > /etc/systemd/system/psvr2-dgpu-power.service
    chmod 0644 /etc/systemd/system/psvr2-dgpu-power.service
    install -m 0644 "$repo_dir/udev/71-psvr2-dgpu-power.rules" /etc/udev/rules.d/
fi

# Monado's compute compositor needs this on AMD so its timewarp queue can run
# ahead of ordinary rendering work. Envision rebuilds replace the binary, so
# re-running the system install after a runtime build reapplies the capability.
# sudo identifies the caller by name/UID; pkexec supplies PKEXEC_UID instead.
target_uid=${SUDO_UID:-${PKEXEC_UID:-}}
if [[ "$target_uid" =~ ^[0-9]+$ ]] && [[ "$target_uid" != 0 ]]; then
    target_home=$(getent passwd "$target_uid" | cut -d: -f6)
    monado_service="$target_home/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
    if [[ -x "$monado_service" ]] && command -v setcap >/dev/null 2>&1; then
        setcap CAP_SYS_NICE=eip "$monado_service"
    else
        echo "WARN Monado service was not found for invoking UID $target_uid; capability not applied." >&2
    fi
fi
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb
# Existing devices receive a generic change event above. Replay the add event
# only for PSVR2 so the dGPU guard starts without requiring a cable reconnect.
udevadm trigger --action=add --subsystem-match=usb \
    --attr-match=idVendor=054c --attr-match=idProduct=0cde
echo "System integration installed and connected PSVR2 devices retriggered."
