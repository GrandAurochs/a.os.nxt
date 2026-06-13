#!/bin/bash
set -e

DISABLE_FLAG="/var/lib/a.os-sync-disabled"

# Ensure the user has root privileges to modify the system state
if [ "$EUID" -ne 0 ]; then
    echo "This command requires administrative privileges."
    exec sudo "$0" "$@"
fi

case "$1" in
    disable)
        touch "$DISABLE_FLAG"
        echo "⛔ A.OS background Flatpak sync has been DISABLED."
        echo "New applications added by the OS will no longer install automatically."
        ;;
    enable)
        rm -f "$DISABLE_FLAG"
        echo "✅ A.OS background Flatpak sync has been ENABLED."
        ;;
    status)
        if [ -f "$DISABLE_FLAG" ]; then
            echo "Status: DISABLED"
        else
            echo "Status: ENABLED"
        fi
        ;;
    *)
        echo "Usage: aos-sync {enable|disable|status}"
        exit 1
        ;;
esac