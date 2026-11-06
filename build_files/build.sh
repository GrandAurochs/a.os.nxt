#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux 
dnf5 install -y \
    plasma-desktop \
    plasma-login-manager \
    plasma-workspace-wayland \
    kde-gtk-config \
    xdg-desktop-portal-kde \
    xdg-desktop-portal-gtk \
    kcm-plasmalogin \
    kdeplasma-addons \
    konsole \
    dolphin \
    kscreen \
    bluedevil \
    kde-print-manager \
    git \
    zsh \
    tailscale \
    plasma-nm \
    kinfocenter \
    plasma-systemmonitor \
    pam-kwallet \
    kwalletmanager \
    plasma-firewall \
    plasma-firewall-firewalld \
    kf6-kauth  \
    qt6-qtwayland \
    qt6-qtbase-devel \
    gcc \
    zstd \
    bubblewrap \
    spectacle \
    cockpit \
    cockpit-ws \
    cockpit-podman \
    cockpit-storaged

dnf5 group install -y development-tools
    
dnf5 install -y polkit-qt6-1

dnf5 remove -y \
    firefox \
    firefox-langpacks \
    fedora-bookmarks \
    code

rm -f /etc/yum.repos.d/vscode.repo

# VSCodium
cat << 'EOF' > /etc/yum.repos.d/vscodium.repo
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF
rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
dnf5 install -y codium

dnf5 reinstall -y firewalld

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging


# OhMyZsh
bash /ctx/omzsh.sh

# Homebrew  non-root setup
if [ -d /usr/share/homebrew ]; then
    chown -R 1000:1000 /usr/share/homebrew
fi

# Flatpak
mkdir -p /usr/share/flatpak/preinstall.d/
mkdir -p /usr/lib/systemd/system/
mkdir -p /usr/libexec/

cp /ctx/apps.preinstall /usr/share/flatpak/preinstall.d/apps.preinstall
cp /ctx/a.os-flatpak-preinstall.service /usr/lib/systemd/system/a.os-flatpak-preinstall.service
cp /ctx/a.os-flatpak-sync.sh /usr/libexec/a.os-flatpak-sync.sh
chmod +x /usr/libexec/a.os-flatpak-sync.sh
cp /ctx/aos-sync /usr/bin/aos-sync
chmod +x /usr/bin/aos-sync

# Plasma Login Manager Migration & Setup
cp /ctx/a.os-plasmalogin-migration.sh /usr/libexec/a.os-plasmalogin-migration.sh
chmod +x /usr/libexec/a.os-plasmalogin-migration.sh
ln -sfn /usr/libexec/a.os-plasmalogin-migration.sh /usr/bin/aos-migrate-login-manager
cp /ctx/a.os-plasmalogin-migration.service /usr/lib/systemd/system/a.os-plasmalogin-migration.service

# Wallpapers
mkdir -p /usr/share/wallpapers
cp -r /ctx/common/Fontainebleau /usr/share/wallpapers/Fontainebleau
rm -rf /usr/share/wallpapers/Fontainebleau/contents/images_dark
rm -rf /usr/share/wallpapers/Default
rm -rf /usr/share/wallpapers/Fedora
rm -rf /usr/share/wallpapers/Next
rm -rf /usr/share/wallpapers/F4*
ln -sfn /usr/share/wallpapers/Fontainebleau /usr/share/wallpapers/Default
ln -sfn /usr/share/wallpapers/Fontainebleau /usr/share/wallpapers/Fedora
ln -sfn /usr/share/wallpapers/Fontainebleau /usr/share/wallpapers/Next

mkdir -p /usr/share/backgrounds
ln -sfn /usr/share/wallpapers/Fontainebleau/contents/images/3080x4072.jpg /usr/share/backgrounds/default.jxl
ln -sfn /usr/share/wallpapers/Fontainebleau/contents/images/3080x4072.jpg /usr/share/backgrounds/default-dark.jxl

# Global Theme (Look and Feel)
mkdir -p /usr/share/plasma/look-and-feel
cp -r /ctx/look-and-feel/app.thebull.aos.desktop /usr/share/plasma/look-and-feel/app.thebull.aos.desktop
ln -sfn app.thebull.aos.desktop /usr/share/plasma/look-and-feel/a.os.desktop
ln -sfn app.thebull.aos.desktop /usr/share/plasma/look-and-feel/org.grandaurochs.aos.desktop

# Set default Look and Feel package for KDE Plasma
mkdir -p /etc/xdg
if [ -f /etc/xdg/kdeglobals ]; then
    if grep -q "LookAndFeelPackage=" /etc/xdg/kdeglobals; then
        sed -i 's/^LookAndFeelPackage=.*/LookAndFeelPackage=app.thebull.aos.desktop/' /etc/xdg/kdeglobals
    elif grep -q "^\[KDE\]" /etc/xdg/kdeglobals; then
        sed -i '/^\[KDE\]/a LookAndFeelPackage=app.thebull.aos.desktop' /etc/xdg/kdeglobals
    else
        printf "\n[KDE]\nLookAndFeelPackage=app.thebull.aos.desktop\n" >> /etc/xdg/kdeglobals
    fi
else
    cat << 'EOF' > /etc/xdg/kdeglobals
[KDE]
LookAndFeelPackage=app.thebull.aos.desktop
EOF
fi

mkdir -p /etc/skel/.config
cp -f /etc/xdg/kdeglobals /etc/skel/.config/kdeglobals

# Polkit Fixes
rm /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy
ln -sf /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.desktop.policy.choice /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy
ln -s /usr/lib64/dbus-1/system-services/org.kde.kcm_firewall.service /usr/share/dbus-1/system-services/org.kde.kcm_firewall.service

# OS Release
cp -f /ctx/os-release /usr/lib/os-release
ln -sfn /usr/lib/os-release /etc/os-release

# Ensure DNF variables (like $releasever) are explicitly pinned for image builders
mkdir -p /etc/dnf/vars
echo "45" > /etc/dnf/vars/releasever

# Pin $releasever to 45 in repo files so external builders
# never evaluate $releasever incorrectly
sed -i 's/\$releasever/45/g' /etc/yum.repos.d/*.repo

# GTK / Flatpak Window Decoration Layout & Portals
mkdir -p /usr/share/glib-2.0/schemas/
cat << 'EOF' > /usr/share/glib-2.0/schemas/99-a-os-button-layout.gschema.override
[org.gnome.desktop.wm.preferences]
button-layout=':minimize,maximize,close'
EOF
glib-compile-schemas /usr/share/glib-2.0/schemas/

mkdir -p /etc/gtk-3.0 /etc/gtk-4.0
cat << 'EOF' > /etc/gtk-3.0/settings.ini
[Settings]
gtk-decoration-layout=:minimize,maximize,close
EOF
cat << 'EOF' > /etc/gtk-4.0/settings.ini
[Settings]
gtk-decoration-layout=:minimize,maximize,close
EOF

mkdir -p /usr/share/xdg-desktop-portal
cat << 'EOF' > /usr/share/xdg-desktop-portal/kde-portals.conf
[preferred]
default=kde
org.freedesktop.impl.portal.Settings=kde;gtk;
EOF

# User Setup & Migration (Ensures existing and new user sessions use 3-button window controls & Flatpak overrides)
mkdir -p /etc/skel/.config/gtk-3.0 /etc/skel/.config/gtk-4.0
cp /etc/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/settings.ini
cp /etc/gtk-4.0/settings.ini /etc/skel/.config/gtk-4.0/settings.ini

cat << 'EOF' > /usr/libexec/a.os-user-setup.sh
#!/bin/bash
# A.OS user environment setup on graphical session start

# 1. Update GSettings / dconf if unset or set to close-only
if command -v gsettings >/dev/null 2>&1; then
    CURRENT_LAYOUT="$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null || true)"
    if [ "$CURRENT_LAYOUT" = "':close'" ] || [ "$CURRENT_LAYOUT" = "'appmenu:close'" ] || [ "$CURRENT_LAYOUT" = "''" ] || [ -z "$CURRENT_LAYOUT" ]; then
        gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close" 2>/dev/null || true
    fi
fi

# 2. Ensure user GTK 3 & 4 settings.ini have gtk-decoration-layout
for v in 3.0 4.0; do
    dir="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-$v"
    ini="$dir/settings.ini"
    mkdir -p "$dir"
    if [ ! -f "$ini" ]; then
        cat << 'SETTINGSEOF' > "$ini"
[Settings]
gtk-decoration-layout=:minimize,maximize,close
SETTINGSEOF
    elif grep -qE '^gtk-decoration-layout\s*=\s*(:close|appmenu:close|icon:close)' "$ini"; then
        sed -i 's/^gtk-decoration-layout\s*=.*/gtk-decoration-layout=:minimize,maximize,close/' "$ini"
    elif ! grep -q '^gtk-decoration-layout' "$ini"; then
        if grep -q '^\[Settings\]' "$ini"; then
            sed -i '/^\[Settings\]/a gtk-decoration-layout=:minimize,maximize,close' "$ini"
        else
            printf "\n[Settings]\ngtk-decoration-layout=:minimize,maximize,close\n" >> "$ini"
        fi
    fi
done

# 3. Ensure Flatpaks can access host GTK settings
if command -v flatpak >/dev/null 2>&1; then
    flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro 2>/dev/null || true
fi

# 4. Set LookAndFeelPackage if unset or set to upstream Fedora/Aurora default
if command -v kwriteconfig6 >/dev/null 2>&1; then
    KDE_GLOBAL="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
    if [ ! -f "$KDE_GLOBAL" ] || ! grep -q '^LookAndFeelPackage=' "$KDE_GLOBAL" || grep -qE '^LookAndFeelPackage=(org\.fedoraproject\.fedora\.desktop|dev\.getaurora\.aurora\.desktop)' "$KDE_GLOBAL"; then
        kwriteconfig6 --file "$KDE_GLOBAL" --group KDE --key LookAndFeelPackage app.thebull.aos.desktop 2>/dev/null || true
    fi
fi
EOF
chmod +x /usr/libexec/a.os-user-setup.sh

mkdir -p /etc/xdg/autostart
cat << 'EOF' > /etc/xdg/autostart/a.os-user-setup.desktop
[Desktop Entry]
Type=Application
Name=A.OS User Setup
Exec=/usr/libexec/a.os-user-setup.sh
NoDisplay=true
X-KDE-autostart-phase=1
EOF


# Tailscale Multi-User Operator Configuration
mkdir -p /usr/lib/systemd/system/user@.service.d/
mkdir -p /etc/sudoers.d/
mkdir -p /etc/profile.d/

cp /ctx/tailscale-set-operator /usr/libexec/tailscale-set-operator
chmod +x /usr/libexec/tailscale-set-operator
cp /ctx/tailscale-operator.conf /usr/lib/systemd/system/user@.service.d/tailscale-operator.conf
cp /ctx/tailscale-operator.sudoers /etc/sudoers.d/tailscale-operator
chmod 0440 /etc/sudoers.d/tailscale-operator
cp /ctx/tailscale-operator.sh /etc/profile.d/tailscale-operator.sh
chmod +x /etc/profile.d/tailscale-operator.sh

# Enable services

systemctl enable podman.socket
systemctl enable cockpit.socket
systemctl enable tailscaled.service
systemctl set-default graphical.target
systemctl enable plasmalogin.service
systemctl enable a.os-plasmalogin-migration.service
systemctl enable a.os-flatpak-preinstall.service
systemctl enable firewalld.service
systemctl enable brew-setup.service
systemctl enable brew-update.timer
systemctl enable brew-upgrade.timer
