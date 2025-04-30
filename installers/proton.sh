#!/bin/bash
# Proton installation script for Docker SteamCMD Server
# Handles installation of Proton (Valve's compatibility tool based on Wine)
#
# This script installs:
# - Proton from GitHub releases
# - Required dependencies
# - Configures environment variables

set -eo pipefail

# Load environment variables if present
if [ -f /etc/environment ]; then
    . /etc/environment
fi

echo "Starting Proton Installation..."

# Verify required parameters are provided
if [ -z "$TARGETARCH" ]; then
    echo "✗ ERROR: TARGETARCH is required but not set"
    exit 1
fi

# Get parameters from environment
PROTON_PATH="/opt/proton"
WINEPREFIX="/home/$CONTAINER_USER/app/Proton"

# ===== Package Variables =====
PACKAGES_PROTON="\
    `# Fake X-Server desktop for Wine/Proton`
    xvfb \
    `# xauth needed with --no-install-recommends`
    xauth \
    `# Python is needed for some Proton scripts`
    python3 \
    python3-pip \
    `# Graphics and common libraries`
    libvulkan1 \
    mesa-vulkan-drivers \
    fontconfig \
    libfreetype6 \
    libpng16-16 \
    libjpeg62-turbo \
    `# Audio support`
    libasound2 \
    `# Common dependencies`
    libglib2.0-0 \
    libdbus-1-3 \
    libnss3 \
    libx11-6 \
    libxss1 \
    libegl1"

PACKAGES_PROTON_I386="\
    `# 32-bit graphics libraries`
    libvulkan1:i386 \
    mesa-vulkan-drivers:i386 \
    `# 32-bit common libraries`
    libfreetype6:i386 \
    libpng16-16:i386 \
    libjpeg62-turbo:i386 \
    libasound2:i386 \
    libglib2.0-0:i386 \
    libdbus-1-3:i386 \
    libnss3:i386 \
    libx11-6:i386 \
    libxss1:i386 \
    libegl1:i386"

# Log configuration
echo "Proton Configuration:"
echo "  Version: ${PROTON_VERSION}"
echo "  Target Architecture: ${TARGETARCH}"
echo "  Install i386 support: ${INSTALL_I386}"

# ===== Step 1: Check for Box86/Box64 on ARM64 =====
echo "Step 1: Checking system compatibility..."

if [ "$TARGETARCH" = "arm64" ]; then
    # Check if box64 is installed
    if ! command -v box64 >/dev/null 2>&1; then
        echo "✗ ERROR: box64 is required for Proton on ARM64"
        exit 1
    fi
    
    # Check for box86 if i386 support is requested
    if [ "$INSTALL_I386" = "true" ] && ! command -v box86 >/dev/null 2>&1; then
        echo "! Warning: box86 not found. Disabling i386 support on ARM64."
        INSTALL_I386="false"
    fi
fi

# ===== Step 2: Set up architecture support =====
echo "Step 2: Setting up architecture support..."

# Add i386 architecture if requested and not on ARM
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    dpkg --add-architecture i386
    apt-get update
    echo "✓ i386 architecture support added"
fi

# ===== Step 3: Install base packages =====
echo "Step 3: Installing Proton dependencies..."

# Install base packages
apt-get install -y --no-install-recommends $PACKAGES_PROTON

# Install i386 packages if requested
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    apt-get install -y --no-install-recommends $PACKAGES_PROTON_I386
    echo "✓ Proton i386 packages installed"
fi

# ===== Step 4: Setup environment variables =====
echo "Step 4: Setting up environment variables..."

# Add Proton configuration to environment file
cat << EOT >> /etc/environment

# Proton configuration
export PROTON_PATH=${PROTON_PATH}
export PROTON_VERSION=${PROTON_VERSION}
export WINEPREFIX=${WINEPREFIX}

# Proton-specific environment variables
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/opt/steam
export STEAM_COMPAT_DATA_PATH=${WINEPREFIX}

# Enable Steam Play debug logging
export PROTON_LOG=1
export PROTON_DUMP_DEBUG_COMMANDS=1
export PROTON_LOG_DIR=/var/log/proton
export PROTON_CRASH_REPORT_DIR=/var/log/proton/crash_reports

# Performance optimizations
export PROTON_NO_ESYNC=0
export PROTON_NO_FSYNC=0
EOT

# Update APP_COMMAND_PREFIX for Proton
if grep -q "APP_COMMAND_PREFIX" /etc/environment; then
    # If already set, append proton run to it
    OLD_PREFIX=$(grep "APP_COMMAND_PREFIX" /etc/environment | cut -d= -f2 | tr -d '"')
    if [ -z "$OLD_PREFIX" ]; then
        sed -i "s/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX=\"proton run\"/" /etc/environment
    else
        # Check if proton run is already in the prefix to avoid duplication
        if [[ "$OLD_PREFIX" != *"proton run"* ]]; then
            # Create the new prefix without adding extra quotes
            NEW_PREFIX="$OLD_PREFIX proton run"
            sed -i "s/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX=\"$NEW_PREFIX\"/" /etc/environment
        fi
    fi
else
    # If not set, create a new entry
    echo "export APP_COMMAND_PREFIX=\"proton run\"" >> /etc/environment
fi

# ===== Step 5: Create required directories =====
echo "Step 5: Creating required directories..."
mkdir -p "${PROTON_PATH}" "${WINEPREFIX}" "/var/log/proton/crash_reports"

# ===== Step 6: Download and install Proton =====
echo "Step 6: Downloading and installing Proton..."

if [ -n "$PROTON_VERSION" ]; then
    # Define download URL
    PROTON_URL="https://github.com/ValveSoftware/Proton/releases/download/proton-${PROTON_VERSION}/proton-${PROTON_VERSION}.tar.gz"
    
    # Download and extract Proton
    curl -sL "$PROTON_URL" -o /tmp/proton.tar.gz
    tar -xzf /tmp/proton.tar.gz -C "${PROTON_PATH}" --strip-components=1
    rm -f /tmp/proton.tar.gz
    
    # Verify installation
    if [ -f "${PROTON_PATH}/proton" ]; then
        echo "✓ Proton installation successful"
    else
        echo "✗ ERROR: Proton installation failed. proton executable not found."
        ls -la "${PROTON_PATH}"
        exit 1
    fi
else
    echo "✗ ERROR: PROTON_VERSION is not set"
    exit 1
fi

# ===== Step 7: Create symlinks =====
echo "Step 7: Setting up Proton symlinks..."

# Create symlinks for standard architecture
if [ "$TARGETARCH" != "arm64" ]; then
    # Create direct symlinks to Proton executables
    ln -sf "${PROTON_PATH}/proton" /usr/local/bin/proton
    ln -sf "${PROTON_PATH}/proton_dist/bin/wine" /usr/local/bin/proton-wine
    ln -sf "${PROTON_PATH}/proton_dist/bin/wine64" /usr/local/bin/proton-wine64
    ln -sf "${PROTON_PATH}/proton_dist/bin/wineserver" /usr/local/bin/proton-wineserver
    echo "✓ Proton symlinks created"
# Setup for ARM64
else
    echo "Setting up ARM64-specific configuration..."
    
    # Create ARM64-specific symlinks using box64/box86
    if command -v box64 >/dev/null 2>&1; then
        # Create a minimal wrapper script for box64 -> proton
        cat > /usr/local/bin/proton << EOF
#!/bin/bash
exec box64 "${PROTON_PATH}/proton" "\$@"
EOF
        chmod +x /usr/local/bin/proton
        
        # Create symlinks for wine components
        ln -sf "${PROTON_PATH}/proton_dist/bin/wine64" /usr/local/bin/proton-wine64
        ln -sf "${PROTON_PATH}/proton_dist/bin/wineserver" /usr/local/bin/proton-wineserver
        
        # Add wine symlink using box86 if available
        if [ "$INSTALL_I386" = "true" ] && command -v box86 >/dev/null 2>&1; then
            cat > /usr/local/bin/proton-wine << EOF
#!/bin/bash
exec box86 "${PROTON_PATH}/proton_dist/bin/wine" "\$@"
EOF
            chmod +x /usr/local/bin/proton-wine
        fi
        
        echo "✓ ARM64-specific Proton symlinks created"
    fi
fi

# ===== Step 8: Setup hooks =====
echo "Step 8: Setting up hooks..."

# Create hooks directories if they don't exist
mkdir -p $HOOK_DIRECTORIES/pre-startup $HOOK_DIRECTORIES/startup

# Copy hook scripts - adjust as needed to match your hook system
if [ -d "/tmp/installers/hooks" ]; then
    cp /tmp/installers/hooks/pre-startup/20_proton_prefix.sh $HOOK_DIRECTORIES/pre-startup/20_proton_prefix.sh 2>/dev/null || echo "! Hook script not found, skipping"
    cp /tmp/installers/hooks/startup/10_xvfb_proton.sh $HOOK_DIRECTORIES/startup/10_xvfb_proton.sh 2>/dev/null || echo "! Hook script not found, skipping"
    chown -R ${CONTAINER_USER}:${CONTAINER_USER} $HOOK_DIRECTORIES/pre-startup $HOOK_DIRECTORIES/startup
fi

# Make everything executable
chown -R ${CONTAINER_USER}:${CONTAINER_USER} $PROTON_PATH

echo "Proton installation complete!"
echo "  Version: ${PROTON_VERSION}"
echo "  Path: ${PROTON_PATH}"
echo "  Prefix: ${WINEPREFIX}"
echo "  i386 Support: ${INSTALL_I386}"

# Re-source environment for current script
. /etc/environment

exit 0
