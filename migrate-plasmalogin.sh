#!/usr/bin/env bash
set -euo pipefail

# Color definitions
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}   A.OS Display Manager Migration: SDDM -> PLM        ${NC}"
echo -e "${BLUE}======================================================${NC}\n"

# 1. Root check
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}ERROR: This migration script requires root privileges.${NC}" >&2
    echo "Please run: sudo $0" >&2
    exit 1
fi

echo -e "${YELLOW}Migrating display manager configuration to Plasma Login Manager...${NC}"

# 2. Stop and disable SDDM if active/enabled
if systemctl is-active --quiet sddm.service 2>/dev/null; then
    echo "Stopping active sddm.service..."
    systemctl stop sddm.service 2>/dev/null || true
fi

echo "Disabling sddm.service..."
systemctl disable sddm.service 2>/dev/null || true

# 3. Clean up stale SDDM symlinks in /etc/systemd/system/
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

# 4. Enable Plasma Login Manager
echo "Enabling plasmalogin.service..."
systemctl enable --force plasmalogin.service

# 5. Set default target to graphical if needed
systemctl set-default graphical.target 2>/dev/null || true

echo -e "\n${GREEN}✓ Successfully migrated display manager to Plasma Login Manager!${NC}"
echo "Plasma Login Manager will be active on your next reboot."
