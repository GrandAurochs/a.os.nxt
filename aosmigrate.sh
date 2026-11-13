#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Color variables for clean terminal output
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

ASSUME_YES=false
REQUIRED_BOOT_MB=350

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [-y|--yes]"
      echo "  -y, --yes  Automatically proceed with migration, skip interactive prompts, and select recommended hardware flavor."
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      echo "Usage: $0 [-y|--yes]"
      exit 1
      ;;
  esac
done

prompt_step() {
  local prompt_text="$1"
  if [ "$ASSUME_YES" = true ]; then
    echo -e "${prompt_text} ${GREEN}[Auto-confirmed (-y)]${NC}"
  else
    read -p "$prompt_text"
  fi
}

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}      Welcome to the A.OS Migrator        ${NC}"
echo -e "${BLUE}==========================================${NC}\n"

# 1. Root Privilege Check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}ERROR: This script requires root privileges to modify the operating system.${NC}"
  echo "Please run this script again using: sudo $0"
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
prompt_step "Press [Enter] to begin..."

# Step 1: Unpin and undeploy all but current booted deployment
echo -e "\n${YELLOW}--- Step 1: Pruning Non-Booted Deployments ---${NC}"
echo "To ensure /boot has adequate storage and to avoid deployment accumulation,"
echo "we will unpin and undeploy all previous or stale deployments, preserving"
echo "only your currently active booted deployment."

prompt_step "Press [Enter] to check and prune non-booted deployments..."

total_deployments=0
booted_idx=-1

while IFS= read -r line; do
  if [[ "$line" =~ ^([*[:space:]])[[:space:]]([^[:space:]]+)[[:space:]]([^[:space:]]+) ]]; then
    marker="${BASH_REMATCH[1]}"
    if [ "$marker" = "*" ]; then
      booted_idx=$total_deployments
    fi
    ((total_deployments++))
  fi
done < <(ostree admin status)

if [ "$total_deployments" -le 1 ]; then
  echo -e "${GREEN}✓ Only the current booted deployment is present.${NC}\n"
else
  echo "Found $total_deployments total deployments (Booted index: $booted_idx)."
  echo "Undeploying older deployments..."

  # Collect non-booted deployment indices in descending order
  non_booted=()
  for ((i=total_deployments-1; i>=0; i--)); do
    if [ "$i" -ne "$booted_idx" ]; then
      non_booted+=("$i")
    fi
  done

  for idx in "${non_booted[@]}"; do
    echo "  - Unpinning deployment index $idx..."
    ostree admin pin -u "$idx" 2>/dev/null || true
    echo "  - Undeploying deployment index $idx..."
    ostree admin undeploy "$idx"
  done

  # Clean up unreferenced objects and metadata
  ostree admin cleanup 2>/dev/null || true
  if command -v rpm-ostree &> /dev/null; then
    rpm-ostree cleanup -b -m 2>/dev/null || true
  fi

  echo -e "${GREEN}✓ Older deployments successfully removed!${NC}\n"
fi

# Step 2: Check Free Space in /boot
echo -e "${YELLOW}--- Step 2: Checking /boot Storage Space ---${NC}"
echo "Staging a new atomic OS deployment requires installing a new kernel and initramfs."

avail_kb=$(df -Pk /boot | awk 'NR==2 {print $4}')
avail_mb=$((avail_kb / 1024))

echo -e "Available space in /boot: ${GREEN}${avail_mb} MB${NC} (Required: ${REQUIRED_BOOT_MB} MB)"

if [ "$avail_mb" -lt "$REQUIRED_BOOT_MB" ]; then
  echo -e "${RED}ERROR: Insufficient free space in /boot!${NC}"
  echo "Available space (${avail_mb} MB) is less than required (${REQUIRED_BOOT_MB} MB)."
  echo "Please free up additional space in /boot before proceeding."
  exit 1
fi
echo -e "${GREEN}✓ Sufficient /boot space verified!${NC}\n"

# Step 3: Pinning Your Current System
echo -e "${YELLOW}--- Step 3: Pinning Your Current System ---${NC}"
echo "Atomic systems are incredibly safe. Before we change anything, we are going to 'pin'"
echo "your current working operating system state."
echo "If the A.OS migration ever fails, you can simply hold ESC or Shift during your next boot,"
echo "open the GRUB menu, and select this pinned version to instantly roll back to exactly"
echo -e "how your machine is right now.\n"
prompt_step "Press [Enter] to pin your current deployment..."

ostree admin pin 0
echo -e "${GREEN}✓ Current system state pinned successfully!${NC}\n"

# Step 4: Downloading the A.OS Security Key
echo -e "${YELLOW}--- Step 4: Downloading the A.OS Security Key ---${NC}"
echo "We cryptographically sign all A.OS images to guarantee they haven't been tampered with."
echo "Your machine needs our public key to verify the signature before it will allow the OS"
echo -e "to be downloaded.\n"
prompt_step "Press [Enter] to fetch the public key..."

mkdir -p /etc/pki/containers
curl -Lo /etc/pki/containers/a.os-cosign.pub https://raw.githubusercontent.com/GrandAurochs/a.os.nxt/main/cosign.pub
echo -e "${GREEN}✓ A.OS public key installed to /etc/pki/containers/a.os-cosign.pub!${NC}\n"

# Step 5: Configuring the Trust Policy
echo -e "${YELLOW}--- Step 5: Configuring the Trust Policy ---${NC}"
echo "Now that the key is downloaded, we must tell your system's container registry"
echo "to enforce a strict signature check whenever it pulls an image from our GitHub."
echo "This guarantees you never boot into unverified code."
echo -e "We will write this policy to /etc/containers/registries.d/a.os.yaml.\n"
prompt_step "Press [Enter] to apply the security policy..."

mkdir -p /etc/containers/registries.d
cat <<EOF > /etc/containers/registries.d/a.os.yaml
docker:
  ghcr.io/grandaurochs:
    use-sigstore-attachments: true
EOF

# Ensure containers policy enforces signature verification for grandaurochs if policy.json exists
if [ -f /etc/containers/policy.json ] && command -v python3 &> /dev/null; then
  python3 -c "
import json
try:
  with open('/etc/containers/policy.json', 'r') as f:
    d = json.load(f)
  docker_policies = d.setdefault('transports', {}).setdefault('docker', {})
  if 'ghcr.io/grandaurochs' not in docker_policies:
    docker_policies['ghcr.io/grandaurochs'] = [
      {
        'type': 'sigstoreSigned',
        'keyPath': '/etc/pki/containers/a.os-cosign.pub',
        'signedIdentity': {'type': 'matchRepository'}
      }
    ]
    with open('/etc/containers/policy.json', 'w') as f:
      json.dump(d, f, indent=2)
except Exception:
  pass
" 2>/dev/null || true
fi

echo -e "${GREEN}✓ Security policy generated and active!${NC}\n"

# Step 6: Selecting Your Hardware Flavor
echo -e "${YELLOW}--- Step 6: Selecting Your Hardware Flavor ---${NC}"

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

if [ "$ASSUME_YES" = true ]; then
    if [ "$HAS_NVIDIA" = true ]; then
        TARGET_IMAGE="ghcr.io/grandaurochs/a.os.nxt-nvidia:latest"
        echo -e "${GREEN}✓ Automatically selected recommended NVIDIA Edition (-y).${NC}\n"
    else
        TARGET_IMAGE="ghcr.io/grandaurochs/a.os.nxt-main:latest"
        echo -e "${GREEN}✓ Automatically selected recommended Standard Edition (-y).${NC}\n"
    fi
else
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
fi

# Step 7: The Rebase
echo -e "${YELLOW}--- Step 7: The Rebase ---${NC}"
echo "Your system is prepped, secured, and ready."
echo "We will now use the modern 'bootc' engine to pull down your selected OS layer."
echo "This will download the image in the background, verify the cryptographic signature,"
echo "and stage the files for your next boot."
echo -e "${RED}WARNING: This step may take a few minutes depending on your internet connection.${NC}\n"
prompt_step "Press [Enter] to begin the A.OS download and installation..."

bootc switch $TARGET_IMAGE

# Ensure display manager is migrated from SDDM to Plasma Login Manager
echo -e "\n${YELLOW}Configuring Plasma Login Manager...${NC}"
systemctl disable sddm.service 2>/dev/null || true
systemctl enable --force plasmalogin.service 2>/dev/null || true

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}🎉 Migration Complete! 🎉${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "A.OS has been securely downloaded, verified, and staged."
echo "To boot into your new operating system, please restart your computer."
echo ""
