#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux 
dnf5 group install -y xfce-desktop-environment
dnf5 install -y \
    lightdm \
    lightdm-gtk-greeter \
    xfce4-terminal \
    NetworkManager-wifi \
    glibc-all-langpacks \
    git \
    zsh

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

mkdir -p /usr/lib/tmpfiles.d


cat <<EOF > /usr/lib/tmpfiles.d/lightdm.conf
# Type  Path                           Mode  UID      GID      Age  Argument
d       /var/lib/lightdm               0750  lightdm  lightdm  -    -
d       /var/lib/lightdm-data          0750  lightdm  lightdm  -    -
d       /var/lib/lightdm-data/lightdm  0750  lightdm  lightdm  -    -
d       /var/cache/lightdm             0750  lightdm  lightdm  -    -
EOF

#### Example for enabling a System Unit File

systemctl enable podman.socket
systemctl set-default graphical.target
systemctl enable lightdm.service