#!/bin/bash
# Box86/Box64 installation script for Docker SteamCMD Server
# Handles installation of Box86 and Box64 for ARM compatibility
#
# This script installs:
# - Box86 for running x86 (32-bit) binaries on ARM
# - Box64 for running x86_64 (64-bit) binaries on ARM
# - Configuration for optimal performance and logging

set -eo pipefail

# Load environment variables if present
if [ -f /etc/environment ]; then
    . /etc/environment
fi

# Display header
echo "------------------------------------------------------- BOX86/BOX64 Installer -----------------------------------------------------------------------" && \

# Get parameters from environment or use defaults
TARGETARCH="${TARGETARCH:-amd64}"
CONTAINER_USER="${CONTAINER_USER:-container}"
LOGS="${LOGS:-/var/log}"

# ===== Package Variables =====
# These can be overridden by setting environment variables before calling the script

# Package definitions with detailed comments for maintainers
PACKAGES_ARM_ONLY="\
    `# required for Box86 > steamcmd`
    libc6:armhf"

# PACKAGES_ARM_BUILD="\
#     `# tools for ARM builds`
#     gcc-arm-linux-gnueabihf \
#     `# compression tools`
#     bzip2 \
#     `# build essentials if needed`
#     build-essential"

# Box86 configuration
BOX86_VERSION="${BOX86_VERSION:-0.3.8}"
BOX86_DEB_URL="${BOX86_DEB_URL:-https://github.com/ryanfortner/box86-debs/raw/master/debian/box86-generic-arm_${BOX86_VERSION}+$(date +%Y%m%d).ee0c949-1_armhf.deb}"

# Box64 configuration
BOX64_VERSION="${BOX64_VERSION:-0.3.5}"
BOX64_DEB_URL="${BOX64_DEB_URL:-https://github.com/ryanfortner/box64-debs/raw/master/debian/box64_${BOX64_VERSION}+$(date +%Y%m%d).96080e4-1_arm64.deb}"

# Skip execution if not on ARM architecture
if [[ "$TARGETARCH" != "arm"* ]]; then
    echo "Box86/Box64 are only required for ARM architectures. Current architecture: $TARGETARCH"
    echo "Skipping Box86/Box64 installation."
    exit 0
fi

echo "Box86/Box64 Configuration:"
echo "  Target Architecture: ${TARGETARCH}"
echo "  Box86 Version: ${BOX86_VERSION}"
echo "  Box86 Package URL: ${BOX86_DEB_URL}"
echo "  Box64 Version: ${BOX64_VERSION}"
echo "  Box64 Package URL: ${BOX64_DEB_URL}"
echo "  ARM Packages: ${PACKAGES_ARM_ONLY}"
echo "  ARM Build Packages: ${PACKAGES_ARM_BUILD}"
echo "  Logs Directory: ${LOGS}"

# ===== Step 1: Setup environment variables =====
echo "Setting up environment variables..."

# Clear previous Box entries if they exist
sed -i '/^# Box86\/Box64 configuration/d' /etc/environment
sed -i '/^BOX86_/d' /etc/environment
sed -i '/^BOX64_/d' /etc/environment
sed -i '/^DEBUGGER=/d' /etc/environment

# Add Box86/Box64 configuration to environment file
echo "" >> /etc/environment
echo "# Box86/Box64 configuration" >> /etc/environment

# Box86 configuration
echo "BOX86_LOG=1" >> /etc/environment
echo "BOX86_TRACE_FILE=${LOGS}/box86.log" >> /etc/environment
echo "DEBUGGER=box86" >> /etc/environment

# Box64 configuration
echo "BOX64_LOG=1" >> /etc/environment
echo "BOX64_DYNAREC_BLEEDING_EDGE=0" >> /etc/environment
echo "BOX64_DYNAREC_BIGBLOCK=0" >> /etc/environment
echo "BOX64_DYNAREC_STRONGMEM=2" >> /etc/environment
echo "BOX64_TRACE_FILE=${LOGS}/box64.log" >> /etc/environment

# Update APP_COMMAND_PREFIX for Box64
if grep -q "APP_COMMAND_PREFIX" /etc/environment; then
    # Get existing prefix, if any
    EXISTING_PREFIX=$(grep "APP_COMMAND_PREFIX" /etc/environment | cut -d= -f2 | tr -d '"')
    
    if [ -z "$EXISTING_PREFIX" ]; then
        # If prefix exists but is empty, set it to box64
        sed -i 's/^APP_COMMAND_PREFIX=.*/APP_COMMAND_PREFIX="box64"/' /etc/environment
    else
        # Check if box64 is already in the prefix to avoid duplication
        if [[ "$EXISTING_PREFIX" != *"box64"* ]]; then
            # If prefix exists and doesn't contain box64, prepend box64
            sed -i 's/^APP_COMMAND_PREFIX=.*/APP_COMMAND_PREFIX="box64 '"$EXISTING_PREFIX"'"/' /etc/environment
        fi
    fi
else
    # If no prefix exists, create one with box64
    echo 'APP_COMMAND_PREFIX="box64"' >> /etc/environment
fi

# ===== Step 2: Install ARM architecture dependencies =====
echo "Setting up ARM architecture and dependencies..."

# Add armhf architecture for Box86 (if not already added)
if ! dpkg --print-foreign-architectures | grep -q "armhf"; then
    echo "Adding armhf architecture for Box86..."
    dpkg --add-architecture armhf
    apt-get update
fi

# Install ARM-specific packages
echo "Installing ARM-specific packages: $PACKAGES_ARM_ONLY"
apt-get install -y --no-install-recommends $PACKAGES_ARM_ONLY

# echo "Installing ARM build packages: $PACKAGES_ARM_BUILD"
# apt-get install -y --no-install-recommends $PACKAGES_ARM_BUILD

# ===== Step 3: Create required directories =====
echo "Creating required directories..."
mkdir -p /usr/local/bin /usr/local/lib/box64 /usr/local/lib/box86

# ===== Step 4: Install Box86 (for x86 32-bit binaries) =====
if [ -n "$BOX86_DEB_URL" ]; then
    echo "Installing Box86..."
    
    echo "Downloading Box86 from: $BOX86_DEB_URL"
    curl -L "$BOX86_DEB_URL" -o /tmp/box86.deb
    
    # Install the package
    echo "Installing Box86..."
    dpkg -i /tmp/box86.deb || apt-get -f install -y
    rm -f /tmp/box86.deb
   
    # Verify installation
    if command -v box86 >/dev/null 2>&1; then
        echo "Box86 installation successful!"
        box86 --version || echo "Box86 version command failed, but package installed"
    else
        echo "Box86 installation may have failed. Command not found."
    fi
fi

# ===== Step 5: Install Box64 (for x86_64 64-bit binaries) =====
if [ -n "$BOX64_DEB_URL" ]; then
    echo "Installing Box64..."
    
    echo "Downloading Box64 from: $BOX64_DEB_URL"
    curl -L "$BOX64_DEB_URL" -o /tmp/box64.deb
    
    # Install the package
    echo "Installing Box64..."
    dpkg -i /tmp/box64.deb || apt-get -f install -y
    rm -f /tmp/box64.deb
    
    # Verify installation
    if command -v box64 >/dev/null 2>&1; then
        echo "Box64 installation successful!"
        box64 --version || echo "Box64 version command failed, but package installed"
    else
        echo "Box64 installation may have failed. Command not found."
    fi
fi

# ===== Step 6: Create helpers and convenience scripts =====
echo "Creating helper scripts..."

# Create a backup of the original file (optional but recommended)
cp /tmp/installers/steamcmd.sh /usr/local/bin/steamcmd
chmod +x "/usr/local/bin/steamcmd"

# ===== Step 7: Log installation results =====
echo "Box86/Box64 installation completed!"

# Re-source environment for current script
. /etc/environment

# Show final environment configuration
echo "Final environment configuration:"
grep -E "^(BOX|DEBUGGER|APP_COMMAND_PREFIX)" /etc/environment

exit 0
