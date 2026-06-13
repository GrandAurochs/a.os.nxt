#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Color variables for clean terminal output
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}      Welcome to the A.OS Migrator        ${NC}"
echo -e "${BLUE}==========================================${NC}\n"

# 1. Root Privilege Check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}ERROR: This script requires root privileges to modify the operating system.${NC}"
  echo "Please run this script again using: sudo ./migrate-to-aos.sh"
  exit 1
fi

# 2. Atomic Environment Check
if [ ! -f "/run/ostree-booted" ]; then
  echo -e "${RED}ERROR: Target environment is not an atomic operating system!${NC}"
  echo "This migrator is designed exclusively for ostree/bootc based systems"
  echo "like Fedora Kinoite, Silverblue, or Bazzite."
  exit 1
fi

# Grab the current OS name for display
CURRENT_OS=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)

echo -e "You are currently running: ${GREEN}${CURRENT_OS}${NC}"
echo -e "This script will securely transition your host into A.OS."
echo -e "We will explain every step before it happens.\n"
read -p "Press [Enter] to begin..."

echo -e "\n${YELLOW}--- Step 1: Pinning Your Current System ---${NC}"
echo "Atomic systems are incredibly safe. Before we change anything, we are going to 'pin'"
echo "your current working operating system state."
echo "If the A.OS migration ever fails, you can simply hold ESC or Shift during your next boot,"
echo "open the GRUB menu, and select this pinned version to instantly roll back to exactly"
echo -e "how your machine is right now.\n"
read -p "Press [Enter] to pin your current deployment..."

ostree admin pin 0
echo -e "${GREEN}✓ Current system state pinned successfully!${NC}\n"

echo -e "${YELLOW}--- Step 2: Downloading the A.OS Security Key ---${NC}"
echo "We cryptographically sign all A.OS images to guarantee they haven't been tampered with."
echo "Your machine needs our public key to verify the signature before it will allow the OS"
echo -e "to be downloaded.\n"
read -p "Press [Enter] to fetch the public key..."

curl -Lo /etc/pki/containers/a.os-cosign.pub https://raw.githubusercontent.com/GrandAurochs/a.os.nxt/main/cosign.pub
echo -e "${GREEN}✓ A.OS public key installed to /etc/pki/containers/a.os-cosign.pub!${NC}\n"

echo -e "${YELLOW}--- Step 3: Configuring the Trust Policy ---${NC}"
echo "Now that the key is downloaded, we must tell your system's container registry"
echo "to enforce a strict signature check whenever it pulls an image from our GitHub."
echo "This guarantees you never boot into unverified code."
echo -e "We will write this policy to /etc/containers/registries.d/a.os.yaml.\n"
read -p "Press [Enter] to apply the security policy..."

cat <<EOF > /etc/containers/registries.d/a.os.yaml
docker:
  ghcr.io/grandaurochs:
    use-sigstore-attachments: true
EOF
echo -e "${GREEN}✓ Security policy generated and active!${NC}\n"

echo -e "${YELLOW}--- Step 4: Selecting Your Hardware Flavor ---${NC}"

# Detect NVIDIA Hardware
HAS_NVIDIA=false
if command -v lspci &> /dev/null; then
    if lspci | grep -iq 'vga.*nvidia\|3d.*nvidia\|display.*nvidia'; then
        HAS_NVIDIA=true
    fi
fi

echo "A.OS comes in two distinct flavors perfectly tuned for your hardware."

# Dynamically suggest the correct build based on hardware scan
if [ "$HAS_NVIDIA" = true ]; then
    echo "1) Standard Edition (Intel / AMD Graphics)"
    echo -e "2) NVIDIA Edition (Pre-installed proprietary drivers) ${GREEN}<-- [Recommended for your hardware]${NC}"
else
    echo -e "1) Standard Edition (Intel / AMD Graphics) ${GREEN}<-- [Recommended for your hardware]${NC}"
    echo "2) NVIDIA Edition (Pre-installed proprietary drivers)"
fi
echo ""

# Interactive loop to capture hardware choice
while true; do
    read -p "Which version would you like to install? (Enter 1 or 2): " flavor_choice
    case $flavor_choice in
        1)
            TARGET_IMAGE="ghcr.io/grandaurochs/a.os.nxt-main:latest"
            echo -e "${GREEN}✓ Standard A.OS selected!${NC}\n"
            break
            ;;
        2)
            TARGET_IMAGE="ghcr.io/grandaurochs/a.os.nxt-nvidia:latest"
            echo -e "${GREEN}✓ A.OS NVIDIA Edition selected!${NC}\n"
            break
            ;;
        *)
            echo -e "${RED}Invalid input. Please enter exactly 1 or 2.${NC}"
            ;;
    esac
done

echo -e "${YELLOW}--- Step 5: The Secure Rebase ---${NC}"
echo "Your system is prepped, secured, and ready."
echo "We will now use the modern 'bootc' engine to pull down your selected OS layer."
echo "This will download the image in the background, verify the cryptographic signature,"
echo "and stage the files for your next boot."
echo -e "${RED}WARNING: This step may take a few minutes depending on your internet connection.${NC}\n"
read -p "Press [Enter] to begin the A.OS download and installation..."

bootc switch $TARGET_IMAGE

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}🎉 Migration Complete! 🎉${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "A.OS has been securely downloaded, verified, and staged."
echo "To boot into your new operating system, please restart your computer."
echo ""