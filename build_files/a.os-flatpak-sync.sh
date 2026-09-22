#!/bin/bash
set -euo pipefail

# Ensure system-wide Flatpak overrides allow read access to host GTK decoration config
if command -v flatpak >/dev/null 2>&1; then
    flatpak override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro 2>/dev/null || true
fi

MANIFEST="/usr/share/flatpak/preinstall.d/apps.preinstall"
STATE_FILE="/var/lib/a.os-preinstall.hash"
DISABLE_FLAG="/var/lib/a.os-sync-disabled"

# 1. Check if the user has manually disabled the sync
if [ -f "$DISABLE_FLAG" ]; then
    echo "A.OS Flatpak sync is disabled by user. Exiting."
    exit 0
fi

# 2. If there is no manifest, there is nothing to do
if [ ! -f "$MANIFEST" ]; then
    exit 0
fi

# 3. Calculate the SHA-256 hash of the current manifest
CURRENT_HASH=$(sha256sum "$MANIFEST" | awk '{print $1}')

# 4. Check against the previous state
if [ -f "$STATE_FILE" ]; then
    LAST_HASH=$(cat "$STATE_FILE")
    if [ "$CURRENT_HASH" == "$LAST_HASH" ]; then
        exit 0
    fi
fi

# 5. Functions to test connectivity
CHECK_HOST="connectivity-check.ubuntu.com"
CHECK_URL="http://connectivity-check.ubuntu.com"
CHECK_INTERVAL=5

is_network_interface_connected() {
    # Check NetworkManager via nmcli if available
    if command -v nmcli >/dev/null 2>&1; then
        if nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -qE '^(ethernet|wifi):connected'; then
            return 0
        fi
    fi

    # Check default route interface operstate (ethernet, wifi, bridge)
    local default_iface
    default_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    if [ -n "$default_iface" ] && [ -f "/sys/class/net/$default_iface/operstate" ]; then
        if [ "$(<"/sys/class/net/$default_iface/operstate")" = "up" ]; then
            case "$default_iface" in
                en*|eth*|em*|wl*|wlan*|br*) return 0 ;;
            esac
        fi
    fi

    # Check /sys/class/net for any UP ethernet/wifi interface with carrier
    for dev in /sys/class/net/{en*,eth*,em*,wl*,wlan*}; do
        if [ -d "$dev" ] && [ -f "$dev/operstate" ] && [ "$(<"$dev/operstate")" = "up" ]; then
            if [ ! -f "$dev/carrier" ] || [ "$(<"$dev/carrier")" = "1" ]; then
                return 0
            fi
        fi
    done

    return 1
}

is_server_pingable() {
    ping -c 1 -W 2 "$CHECK_HOST" >/dev/null 2>&1
}

is_server_http_ok() {
    local status
    status=$(curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "$CHECK_URL" 2>/dev/null || true)
    [ "$status" = "204" ] || [ "$status" = "200" ]
}

wait_for_connectivity() {
    local last_state=""
    trap 'echo "A.OS Flatpak sync: Received termination signal. Exiting."; exit 0' SIGTERM SIGINT

    while true; do
        if ! is_network_interface_connected; then
            if [ "$last_state" != "waiting_interface" ]; then
                echo "Waiting for active Wi-Fi or Ethernet connection..."
                last_state="waiting_interface"
            fi
        else
            local ping_ok=0
            local http_ok=0

            if is_server_pingable; then
                ping_ok=1
            fi

            if is_server_http_ok; then
                http_ok=1
            fi

            if [ "$ping_ok" -eq 1 ] && [ "$http_ok" -eq 1 ]; then
                echo "Active network connection detected."
                echo "Connectivity verified: ping and HTTP test to Ubuntu Connectivity Test server ($CHECK_HOST) succeeded."
                return 0
            fi

            if [ "$last_state" != "waiting_server" ]; then
                echo "Active network interface detected. Testing connection to Ubuntu Connectivity Test server ($CHECK_HOST)..."
                last_state="waiting_server"
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# 6. Wait until a device is connected to the internet (active Wi-Fi/Ethernet + ping + HTTP check to Ubuntu Connectivity Test server)
echo "Preinstall manifest changes detected. Preparing to sync Flatpaks..."
wait_for_connectivity

# 7. Sync Flatpaks
echo "Syncing Flatpaks..."
/usr/bin/flatpak preinstall -y

# 8. Save the new state
echo "$CURRENT_HASH" > "$STATE_FILE"
echo "A.OS Flatpak preinstallation complete."
