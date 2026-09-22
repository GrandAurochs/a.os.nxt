#!/bin/bash
set -euo pipefail

# Ensure script runs as root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: Migration script must be run as root." >&2
    exit 1
fi

echo "Checking display manager configuration..."

MIGRATION_NEEDED=false

# Check if SDDM is enabled or referenced in /etc/systemd/system
if [ -L /etc/systemd/system/display-manager.service ]; then
    DM_TARGET=$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)
    if [[ "$DM_TARGET" == *"sddm"* ]]; then
        MIGRATION_NEEDED=true
    fi
fi

if [ -f /etc/systemd/system/graphical.target.wants/sddm.service ] || \
   [ -L /etc/systemd/system/graphical.target.wants/sddm.service ] || \
   [ -f /etc/systemd/system/multi-user.target.wants/sddm.service ] || \
   [ -L /etc/systemd/system/multi-user.target.wants/sddm.service ]; then
    MIGRATION_NEEDED=true
fi

if systemctl is-enabled sddm.service >/dev/null 2>&1; then
    MIGRATION_NEEDED=true
fi

# Also migrate if display-manager.service is missing or broken
if [ ! -e /etc/systemd/system/display-manager.service ]; then
    MIGRATION_NEEDED=true
fi

# Force migration if requested or if migration is needed
if [ "${1:-}" = "--force" ] || [ "$MIGRATION_NEEDED" = true ]; then
    echo "Migrating display manager from SDDM to Plasma Login Manager..."

    # Stop SDDM if it happens to be running
    if systemctl is-active --quiet sddm.service 2>/dev/null; then
        echo "Stopping sddm.service..."
        systemctl stop sddm.service 2>/dev/null || true
    fi

    # Disable SDDM service
    echo "Disabling sddm.service..."
    systemctl disable sddm.service 2>/dev/null || true

    # Clean up any lingering SDDM symlinks or unit references in /etc
    for link in \
        /etc/systemd/system/display-manager.service \
        /etc/systemd/system/graphical.target.wants/sddm.service \
        /etc/systemd/system/multi-user.target.wants/sddm.service; do
        if [ -L "$link" ] || [ -f "$link" ]; then
            target=$(readlink "$link" 2>/dev/null || true)
            if [[ "$target" == *"sddm"* ]] || [[ "$link" == *"sddm"* ]]; then
                echo "Removing stale link: $link -> $target"
                rm -f "$link"
            fi
        fi
    done

    # Enable Plasma Login Manager
    echo "Enabling plasmalogin.service..."
    systemctl enable --force plasmalogin.service

    # Optionally start if --start was passed
    if [ "${1:-}" = "--start" ] || [ "${2:-}" = "--start" ]; then
        echo "Starting plasmalogin.service..."
        systemctl start plasmalogin.service 2>/dev/null || true
    fi

    echo "Display manager successfully migrated to Plasma Login Manager."
else
    echo "Plasma Login Manager is already configured; no migration needed."
fi
