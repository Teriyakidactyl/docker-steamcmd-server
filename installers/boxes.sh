#!/bin/bash
# Box86/Box64 installation script for Docker SteamCMD Server
# Handles installation of Box86 and Box64 for ARM compatibility

set -eo pipefail

# Load environment variables if present
if [ -f /etc/environment ]; then
    . /etc/environment
fi

# Display header
echo "------------------------------------------------------- BOX86/BOX64 Installer -----------------------------------------------------------------------"

# Verify required parameters are provided
if [ -z "$TARGETARCH" ]; then
    echo "✗ ERROR: TARGETARCH is required but not set"
    exit 1
fi

if [ -z "$BOX86_DEB_URL" ]; then
    echo "✗ ERROR: BOX86_DEB_URL is required but not set"
    exit 1
fi

if [ -z "$BOX64_DEB_URL" ]; then
    echo "✗ ERROR: BOX64_DEB_URL is required but not set"
    exit 1
fi

echo "Box86/Box64 Configuration:"
echo "  Target Architecture: $TARGETARCH"
echo "  Box86 Package URL: $BOX86_DEB_URL"
echo "  Box64 Package URL: $BOX64_DEB_URL"

# ===== Step 1: Setup environment variables =====
echo "Setting up environment variables..."

# Add Box86/Box64 configuration to environment file
cat << EOT >> /etc/environment

# Box86/Box64 configuration
# Box86 configuration
export BOX86_LOG=1
export BOX86_TRACE_FILE=/var/log/box86.log
export DEBUGGER=box86

# Box64 configuration
export BOX64_LOG=1
export BOX64_DYNAREC_BLEEDING_EDGE=0
export BOX64_DYNAREC_BIGBLOCK=0
export BOX64_DYNAREC_STRONGMEM=2
export BOX64_TRACE_FILE=/var/log/box64.log
EOT

# Update APP_COMMAND_PREFIX for Box64
if grep -q "APP_COMMAND_PREFIX" /etc/environment; then
    # Get existing prefix, if any
    EXISTING_PREFIX=$(grep "APP_COMMAND_PREFIX" /etc/environment | cut -d= -f2 | tr -d '"')
    
    if [ -z "$EXISTING_PREFIX" ]; then
        # If prefix exists but is empty, set it to box64
        sed -i 's/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX="box64"/' /etc/environment
    else
        # Check if box64 is already in the prefix to avoid duplication
        if [[ "$EXISTING_PREFIX" != *"box64"* ]]; then
            # If prefix exists and doesn't contain box64, prepend box64
            sed -i 's/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX="box64 '"$EXISTING_PREFIX"'"/' /etc/environment
        fi
    fi
else
    # If no prefix exists, create one with box64
    echo 'export APP_COMMAND_PREFIX="box64"' >> /etc/environment
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
echo "Installing ARM-specific packages: libc6:armhf"
apt-get install -y --no-install-recommends libc6:armhf

# ===== Step 3: Create required directories =====
echo "Creating required directories..."
mkdir -p /usr/local/bin /usr/local/lib/box64 /usr/local/lib/box86

# ===== Step 4: Install Box86 (for x86 32-bit binaries) =====
echo "Installing Box86..."
echo "Downloading Box86 from: $BOX86_DEB_URL"
curl -L "$BOX86_DEB_URL" -o /tmp/box86.deb

# Install the package
echo "Installing Box86..."
dpkg -i /tmp/box86.deb || apt-get -f install -y
rm -f /tmp/box86.deb

# ===== Step 5: Install Box64 (for x86_64 64-bit binaries) =====
echo "Installing Box64..."
echo "Downloading Box64 from: $BOX64_DEB_URL"
curl -L "$BOX64_DEB_URL" -o /tmp/box64.deb

# Install the package
echo "Installing Box64..."
dpkg -i /tmp/box64.deb || apt-get -f install -y
rm -f /tmp/box64.deb

# ===== Step 6: Tests ==========================================
echo "Running verification tests..."

# Test Box86 installation
if command -v box86 >/dev/null 2>&1; then
    echo "✓ Box86 command found"
    box86 --version > /tmp/box86_version.txt || { 
        echo "✗ ERROR: Box86 version command failed"
        exit 1
    }
    echo "✓ Box86 version: $(cat /tmp/box86_version.txt)"
else
    echo "✗ ERROR: Box86 installation failed - command not found"
    exit 1
fi

# Test Box64 installation
if command -v box64 >/dev/null 2>&1; then
    echo "✓ Box64 command found"
    box64 --version > /tmp/box64_version.txt || {
        echo "✗ ERROR: Box64 version command failed"
        exit 1
    }
    echo "✓ Box64 version: $(cat /tmp/box64_version.txt)"
else
    echo "✗ ERROR: Box64 installation failed - command not found"
    exit 1
fi

echo "✓ All installation tests passed successfully!"

# ===== Step 7: Log installation results =====
echo "Box86/Box64 installation completed!"

# Re-source environment for current script
. /etc/environment

# Show final environment configuration
echo "Final environment configuration:"
cat /etc/environment

exit 0