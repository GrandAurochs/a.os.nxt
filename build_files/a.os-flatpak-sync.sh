#!/bin/bash
set -euo pipefail

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

# 5. If we reach this point, the manifest changed.
echo "Preinstall manifest changes detected. Syncing Flatpaks..."
/usr/bin/flatpak preinstall -y

# 6. Save the new state
echo "$CURRENT_HASH" > "$STATE_FILE"