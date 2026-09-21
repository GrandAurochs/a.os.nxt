# Set Tailscale operator to current user for interactive sessions if UID >= 1000
if [ "${EUID:-$(id -u)}" -ge 1000 ] && [ -n "${USER:-}" ]; then
    # Ensure current user is the Tailscale operator
    sudo -n /usr/bin/tailscale set --operator="$USER" &>/dev/null || true
fi
