#!/usr/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=""
framework=false

usage() {
    cat <<'EOF'
Usage:
  ./install.sh --user [--framework16-rx7700s]
  sudo ./install.sh --system [--framework16-rx7700s]

--user installs launchers, scripts, settings, and user services.
--system installs PSVR2 udev permissions and optional AMD/Framework services.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --user|--system) mode=${arg#--} ;;
        --framework16-rx7700s) framework=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n "$mode" ]] || { usage >&2; exit 2; }

if [[ "$mode" == user ]]; then
    [[ ${EUID} -ne 0 ]] || { echo "Run --user as your normal account." >&2; exit 1; }
    install -d "$HOME/.local/bin" "$HOME/.local/lib/psvr2-linux" \
        "$HOME/.config/psvr2-linux" "$HOME/.config/systemd/user" \
        "$HOME/.config/wireplumber/wireplumber.conf.d" \
        "$HOME/.local/share/applications" "$HOME/.local/share/psvr2-setup"
    install -m 0755 "$repo_dir"/bin/* "$HOME/.local/bin/"
    install -m 0644 "$repo_dir/lib/psvr2-common.sh" "$HOME/.local/lib/psvr2-linux/common.sh"
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

    # Apply LVRA's DisplayPort dropout fix only to the configured HMD sink.
    # shellcheck disable=SC1090
    source "$HOME/.config/psvr2-linux/settings.env"
    audio_rule="$HOME/.config/wireplumber/wireplumber.conf.d/51-psvr2-displayport-audio.conf"
    if [[ -n "${VR_AUDIO_SINK:-}" ]]; then
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
    systemctl --user enable psvr2-autostart-monitor.service \
        psvr2-steamvr-bridge.path psvr2-steamvr-maintenance.path \
        psvr2-steam-vr-sync.path
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    echo "User integration installed. Review ~/.config/psvr2-linux/settings.env."
    exit 0
fi

[[ ${EUID} -eq 0 ]] || { echo "Run --system with sudo." >&2; exit 1; }
install -m 0644 "$repo_dir/udev/70-psvr2.rules" /etc/udev/rules.d/70-psvr2.rules
if $framework; then
    install -d /usr/local/libexec
    install -m 0755 "$repo_dir/systemd/system/psvr2-dgpu-power" /usr/local/libexec/
    install -m 0644 "$repo_dir/systemd/system/psvr2-dgpu-power.service" /etc/systemd/system/
    install -m 0644 "$repo_dir/udev/71-psvr2-dgpu-power.rules" /etc/udev/rules.d/
fi

# Monado's compute compositor needs this on AMD so its timewarp queue can run
# ahead of ordinary rendering work. Envision rebuilds replace the binary, so
# re-running the system install after a Clean Build reapplies the capability.
target_user=${SUDO_USER:-}
if [[ -n "$target_user" ]]; then
    target_home=$(getent passwd "$target_user" | cut -d: -f6)
    monado_service="$target_home/.local/share/envision/prefixes/psvr2-toolkit-monado/bin/monado-service"
    if [[ -x "$monado_service" ]] && command -v setcap >/dev/null 2>&1; then
        setcap CAP_SYS_NICE=eip "$monado_service"
    fi
fi
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb
echo "System integration installed. Reconnect or power-cycle PSVR2."
