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
    sddm \
    plasma-workspace-wayland \
    sddm-kcm \
    konsole \
    dolphin \
    NetworkManager-wifi \
    glibc-all-langpacks \
    git \
    zsh \
    tailscale
dnf5 remove -y \
    firefox \
    firefox-langpacks \
    fedora-bookmarks

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

sed -i 's|SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

git clone https://github.com/ohmyzsh/ohmyzsh.git /etc/skel/.oh-my-zsh
cp /etc/skel/.oh-my-zsh/templates/zshrc.zsh-template /etc/skel/.zshrc
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="darkblood"/' /etc/skel/.zshrc

mkdir -p /usr/share/flatpak/preinstall.d/
mkdir -p /usr/lib/systemd/system/
mkdir -p /usr/libexec/

cp /ctx/apps.preinstall /usr/share/flatpak/preinstall.d/apps.preinstall
cp /ctx/a.os-flatpak-preinstall.service /usr/lib/systemd/system/a.os-flatpak-preinstall.service
cp /ctx/a.os-flatpak-sync.sh /usr/libexec/a.os-flatpak-sync.sh
chmod +x /usr/libexec/a.os-flatpak-sync.sh
cp /ctx/aos-sync /usr/bin/aos-sync
chmod +x /usr/bin/aos-sync

mkdir -p /usr/lib/sddm/sddm.conf.d/
cp /ctx/sddm-custom.conf /usr/lib/sddm/sddm.conf.d/sddm-custom.conf

# Enable services

systemctl enable podman.socket
systemctl set-default graphical.target
systemctl enable sddm.service
systemctl enable a.os-flatpak-preinstall.service