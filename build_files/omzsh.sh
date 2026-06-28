#!/bin/bash

set -ouex pipefail

#Set default user shell to zsh


sed -i 's|SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd

git clone https://github.com/ohmyzsh/ohmyzsh.git /etc/skel/.oh-my-zsh
cp /etc/skel/.oh-my-zsh/templates/zshrc.zsh-template /etc/skel/.zshrc
sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="darkblood"|' /etc/skel/.zshrc

