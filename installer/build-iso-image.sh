#!/usr/bin/env bash
set -exo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Install Live ISO packages
dnf5 install -y \
    dracut-live \
    livesys-scripts \
    anaconda-live \
    grub2-efi-x64-cdboot \
    yad \
    libblockdev-dm

# 2. Configure Live session for KDE
if [ -f /etc/sysconfig/livesys ]; then
    sed -i "s/^livesys_session=.*/livesys_session=kde/" /etc/sysconfig/livesys
else
    echo "livesys_session=kde" > /etc/sysconfig/livesys
fi
systemctl enable livesys.service livesys-late.service

# 3. Detect Kernel and generate Live-capable initramfs
kernel=$(kernel-install list --json pretty 2>/dev/null | jq -r '.[] | select(.has_kernel == true) | .version' | head -n 1 || true)
if [ -z "$kernel" ] || [ "$kernel" = "null" ]; then
    kernel=$(basename "$(ls -d /usr/lib/modules/* 2>/dev/null | head -n 1)")
fi
echo "Generating Live initramfs for kernel: ${kernel}"
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

# 4. Copy EFI binaries to /boot/efi where Titanoboa and EFI firmware expect them
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/
if [ -f /boot/efi/EFI/fedora/grubx64.efi ]; then
    cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi 2>/dev/null || true
fi

# 5. Place iso.yaml for Titanoboa
mkdir -p /usr/lib/bootc-image-builder
cp "$SCRIPT_DIR/iso.yaml" /usr/lib/bootc-image-builder/iso.yaml

# 6. Configure Anaconda interactive defaults kickstart
mkdir -p /usr/share/anaconda
cat << 'EOF' > /usr/share/anaconda/interactive-defaults.ks
ostreecontainer --url=ghcr.io/grandaurochs/a.os.nxt-main:latest --transport=registry

%post --erroronfail
# Ensure container signature policy and remote origin are configured
sed -i 's|container-image-reference=.*|container-image-reference=ostree-image-signed:docker://ghcr.io/grandaurochs/a.os.nxt-main:latest|' /ostree/deploy/default/deploy/*.origin
%end
EOF

# 7. Larger tmpfs for /var/tmp on live system (prevents out-of-space during ostree deployment)
mkdir -p /var/tmp
cat << 'EOF' > /etc/systemd/system/var-tmp.mount
[Unit]
Description=Larger tmpfs for /var/tmp on live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%,nr_inodes=1m,x-systemd.graceful-option=usrquota

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount

# 8. Setup Live Session Welcome Dialog & Launcher
cat << 'EOF' > /usr/bin/on_gui_login.sh
#!/usr/bin/env bash
# Welcome dialog in a.OS Live environment

# Check if we are running in a live session
if [ ! -d /run/initramfs/live ]; then
    exit 0
fi

yad \
    --title="Welcome to a.OS Live" \
    --window-icon="preferences-desktop" \
    --center \
    --width=450 \
    --text="\n<b>Welcome to a.OS!</b>\n\nYou are running the live desktop environment.\nYou can explore the desktop or install a.OS directly to disk.\n" \
    --button="Install a.OS:10" \
    --button="Try a.OS:0"
RETVAL=$?

if [ "$RETVAL" -eq 10 ]; then
    liveinst & disown $!
fi
EOF
chmod +x /usr/bin/on_gui_login.sh

mkdir -p /etc/skel/.config/autostart
cat << 'EOF' > /etc/skel/.config/autostart/a.os-live-welcome.desktop
[Desktop Entry]
Type=Application
Name=a.OS Live Welcome
Exec=/usr/bin/on_gui_login.sh
Icon=preferences-desktop
Terminal=false
NoDisplay=false
X-KDE-autostart-phase=2
EOF

# 9. Disable live-incompatible services in the live image
for s in tailscaled.service brew-upgrade.timer brew-update.timer brew-setup.service; do
    systemctl disable "$s" 2>/dev/null || true
done

# 10. Clean package cache
dnf5 clean all
