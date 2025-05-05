#!/bin/bash
# Proton GE installation script for Docker SteamCMD Server
# Handles installation of Proton GE (Glorious Eggroll's custom Proton build)
#
# This script installs:
# - Proton GE from GitHub releases
# - Required dependencies
# - Configures environment variables
#
# This script expects PROTON_VERSION to be passed as a build argument or environment variable,
# representing the base version number (e.g., "8.0-5").

set -eo pipefail

# Load environment variables if present
if [ -f /etc/environment ]; then
    . /etc/environment
fi

echo "Starting Proton GE Installation..."

# Verify required parameters are provided
if [ -z "$TARGETARCH" ]; then
    echo "✗ ERROR: TARGETARCH is required but not set"
    exit 1
fi

# PROTON_VERSION must be provided via build arg or environment
if [ -z "$PROTON_VERSION" ]; then
    echo "✗ ERROR: PROTON_VERSION is required but not set. Please provide the base version (e.g., '8.0-5')."
    exit 1
fi

# Get parameters from environment or use defaults
PROTON_PATH="${PROTON_PATH:-/opt/proton}" # Use default if not set
WINEPREFIX="${WINEPREFIX:-/home/$CONTAINER_USER/app/Proton}" # Use default if not set
INSTALL_I386="${INSTALL_I386:-true}" # Default to true if not set
CONTAINER_USER="${CONTAINER_USER:-steam}" # Default to steam if not set
HOOK_DIRECTORIES="${HOOK_DIRECTORIES:-/opt/steam/hooks}" # Default hook directory

# Construct the full Proton GE tag name from the provided PROTON_VERSION
# This tag is needed for downloading the correct release archive.
# Example: If PROTON_VERSION is "9.26", we need "GE-Proton9-26"
# Strip any prefixes if present
VERSION_CLEANED="${PROTON_VERSION#GE-}"
VERSION_CLEANED="${VERSION_CLEANED#Proton}"
VERSION_CLEANED="${VERSION_CLEANED#-}"

# Replace dots with hyphens in the version number
VERSION_FORMATTED="${VERSION_CLEANED//./-}"

# Construct the final tag name
PROTON_TAG_NAME="GE-Proton${VERSION_FORMATTED}"

# Log configuration
echo "Proton GE Configuration:"
echo "    Requested Version: ${PROTON_VERSION}"
echo "    Full GE Tag Name: ${PROTON_TAG_NAME}"
echo "    Target Architecture: ${TARGETARCH}"
echo "    Install i386 support: ${INSTALL_I386}"
echo "    Proton Path: ${PROTON_PATH}"
echo "    Wineprefix: ${WINEPREFIX}"


# ===== Package Variables =====
PACKAGES_PROTON="\
    `# Fake X-Server desktop for Wine/Proton - needed for server`
    xvfb \
    `# xauth needed with --no-install-recommends with wine`
    xauth \
    `# Font configuration needed by many Windows applications`
    fontconfig \
    `# Libraries frequently needed by Windows applications`
    libfreetype6 \
    libpng16-16 \
    libjpeg62-turbo \
    libglib2.0-0 \
    libdbus-1-3 \
    libnss3 \
    libx11-6"

# Commented out unnecessary packages for headless server
# `# Graphics libraries - not needed for headless server`
# libvulkan1 \
# mesa-vulkan-drivers \
# `# Audio libraries - not needed for headless server`
# libasound2 \
# `# Optional eye-candy related libraries`
# libxss1 \
# libegl1"

PACKAGES_PROTON_I386="\
    `# 32-bit libraries needed for i386 Wine`
    libfreetype6:i386 \
    libpng16-16:i386 \
    libjpeg62-turbo:i386 \
    `# Additional dependencies for 32-bit applications`
    libglib2.0-0:i386 \
    libdbus-1-3:i386 \
    libnss3:i386 \
    libx11-6:i386"

# Commented out unnecessary i386 packages
# `# 32-bit graphics libraries - not needed for headless server`
# libvulkan1:i386 \
# mesa-vulkan-drivers:i386 \
# `# 32-bit audio - not needed for headless server`
# libasound2:i386 \
# `# Optional 32-bit libraries`
# libxss1:i386 \
# libegl1:i386"


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
    echo "✓ ARM64 compatibility check passed"
else
    echo "✓ System compatibility check passed"
fi

# ===== Step 2: Set up architecture support =====
echo "Step 2: Setting up architecture support..."

# Add i386 architecture if requested and not on ARM
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    dpkg --add-architecture i386
    apt-get update
    echo "✓ i386 architecture support added"
else
     echo "✓ i386 architecture support not added (either not requested or on ARM64)"
fi


# ===== Step 3: Install base packages =====
echo "Step 3: Installing Proton dependencies..."

# Install base packages
apt-get install -y --no-install-recommends $PACKAGES_PROTON
echo "✓ Proton base packages installed"

# Install i386 packages if requested and not on ARM
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    apt-get install -y --no-install-recommends $PACKAGES_PROTON_I386
    echo "✓ Proton i386 packages installed"
else
    echo "✓ Proton i386 packages not installed (either not requested or on ARM64)"
fi


# ===== Step 4: Setup environment variables =====
echo "Step 4: Setting up environment variables..."

# Add Proton configuration to environment file
# Use tee with -a for appending and sudo for permissions if needed
tee -a /etc/environment > /dev/null << EOT

# Proton GE configuration
export PROTON_PATH=${PROTON_PATH}
export PROTON_VERSION=${PROTON_VERSION} # Set to the input version string provided by the user
export WINEPREFIX=${WINEPREFIX}

# Proton-specific environment variables
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/opt/steam # Assuming steam is installed here
export STEAM_COMPAT_DATA_PATH=${WINEPREFIX}

# Enable Steam Play debug logging
export PROTON_LOG=1
export PROTON_LOG_DIR=/var/log/proton
EOT
echo "✓ Proton environment variables added to /etc/environment"

# Commented out unnecessary environment variables for headless server
# export PROTON_DUMP_DEBUG_COMMANDS=1
# export PROTON_CRASH_REPORT_DIR=/var/log/proton/crash_reports
#
# # Performance optimizations - may not be needed for all servers
# export PROTON_NO_ESYNC=0
# export PROTON_NO_FSYNC=0

# Update APP_COMMAND_PREFIX for Proton
echo "Updating APP_COMMAND_PREFIX..."
if grep -q "export APP_COMMAND_PREFIX=" /etc/environment; then
    # If already set, append proton run to it
    # Use sed to modify the existing line
    sed -i '/export APP_COMMAND_PREFIX=/ {
        s/export APP_COMMAND_PREFIX="\(.*\)"/export APP_COMMAND_PREFIX="\1 proton run"/
        t # jump to end if substitution was made
        s/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX="proton run"/ # handle case without quotes
    }' /etc/environment
    echo "✓ APP_COMMAND_PREFIX updated in /etc/environment"
else
    # If not set, create a new entry
    echo 'export APP_COMMAND_PREFIX="proton run"' >> /etc/environment
    echo "✓ APP_COMMAND_PREFIX added to /etc/environment"
fi


# ===== Step 5: Create required directories =====
echo "Step 5: Creating required directories..."
mkdir -p "${PROTON_PATH}" "${WINEPREFIX}" "/var/log/proton"
echo "✓ Required directories created"

# Directory for crash reports only if needed
# mkdir -p "/var/log/proton/crash_reports"

# ===== Step 6: Download and install Proton GE =====
echo "Step 6: Downloading and installing Proton GE..."

# Define download URL for Proton GE using the constructed tag name
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_TAG_NAME}/${PROTON_TAG_NAME}.tar.gz"

echo "Downloading Proton GE from: ${PROTON_URL}"

# Download and extract Proton GE
mkdir -p /tmp/proton_ge
curl -sL "$PROTON_URL" -o /tmp/proton_ge/proton.tar.gz
if [ $? -ne 0 ]; then
    echo "✗ ERROR: Failed to download Proton GE from ${PROTON_URL}"
    rm -rf /tmp/proton_ge # Clean up temp directory on failure
    exit 1
fi
echo "✓ Download complete"

echo "Extracting Proton GE..."
# Extract to temporary location first
tar -xzf /tmp/proton_ge/proton.tar.gz -C /tmp/proton_ge
if [ $? -ne 0 ]; then
    echo "✗ ERROR: Failed to extract Proton GE archive"
    rm -rf /tmp/proton_ge # Clean up temp directory on failure
    exit 1
fi
echo "✓ Extraction complete"

# Move content to final location
echo "Moving extracted files to ${PROTON_PATH}..."
# The extracted directory name is the full tag name
mv /tmp/proton_ge/${PROTON_TAG_NAME}/* "${PROTON_PATH}/"
rm -rf /tmp/proton_ge # Clean up temp directory
echo "✓ Files moved"

# Verify installation
if [ -f "${PROTON_PATH}/proton" ]; then
    echo "✓ Proton GE installation successful"
else
    echo "✗ ERROR: Proton GE installation failed. proton executable not found."
    ls -la "${PROTON_PATH}"
    exit 1
fi

# ===== Step 7: Create symlinks =====
echo "Step 7: Setting up Proton GE symlinks..."

# Create symlinks for standard architecture
if [ "$TARGETARCH" != "arm64" ]; then
    # Create direct symlinks to Proton executables
    ln -sf "${PROTON_PATH}/proton" /usr/local/bin/proton
    ln -sf "${PROTON_PATH}/files/bin/wine" /usr/local/bin/proton-wine
    ln -sf "${PROTON_PATH}/files/bin/wine64" /usr/local/bin/proton-wine64
    ln -sf "${PROTON_PATH}/files/bin/wineserver" /usr/local/bin/proton-wineserver
    echo "✓ Proton GE symlinks created for standard architecture"
# Setup for ARM64
else
    echo "Setting up ARM64-specific configuration..."

    # Create ARM64-specific symlinks using box64/box86
    if command -v box64 >/dev/null 2>&1; then
        # Create a minimal wrapper script for box64 -> proton
        cat > /usr/local/bin/proton << EOF
#!/bin/bash
# Wrapper script to run proton via box64
exec box64 "${PROTON_PATH}/proton" "\$@"
EOF
        chmod +x /usr/local/bin/proton
        echo "✓ ARM64 proton wrapper script created"

        # Create symlinks for wine components
        ln -sf "${PROTON_PATH}/files/bin/wine64" /usr/local/bin/proton-wine64
        ln -sf "${PROTON_PATH}/files/bin/wineserver" /usr/local/bin/proton-wineserver
        echo "✓ ARM64 proton-wine64 and proton-wineserver symlinks created"

        # Add wine symlink using box86 if available
        if [ "$INSTALL_I386" = "true" ] && command -v box86 >/dev/null 2>&1; then
            cat > /usr/local/bin/proton-wine << EOF
#!/bin/bash
# Wrapper script to run wine via box86
exec box86 "${PROTON_PATH}/files/bin/wine" "\$@"
EOF
            chmod +x /usr/local/bin/proton-wine
            echo "✓ ARM64 proton-wine symlink created via box86"
        else
             echo "✓ ARM64 proton-wine symlink not created (box86 not available or i386 not requested)"
        fi
    else
        echo "✗ ERROR: box64 not found. Cannot setup ARM64 symlinks."
        exit 1 # Exit if box64 is required but not found on ARM64
    fi
fi

# ===== Step 8: Setup hooks =====
echo "Step 8: Setting up hooks..."

# Create hooks directories if they don't exist
mkdir -p "$HOOK_DIRECTORIES/pre-startup" "$HOOK_DIRECTORIES/startup"
echo "✓ Hook directories created"

# Copy hook scripts - follow the same pattern as the Wine script
# Use -f to force overwrite if they exist
if [ -d "/tmp/installers/hooks" ]; then
    echo "Copying hook scripts from /tmp/installers/hooks..."
    cp -f /tmp/installers/hooks/pre-startup/20_proton_prefix.sh "$HOOK_DIRECTORIES/pre-startup/20_proton_prefix.sh" 2>/dev/null || echo "! Hook script 20_proton_prefix.sh not found, skipping"
    cp -f /tmp/installers/hooks/startup/10_xvfb_proton.sh "$HOOK_DIRECTORIES/startup/10_xvfb_proton.sh" 2>/dev/null || echo "! Hook script 10_xvfb_proton.sh not found, skipping"
    # Ensure correct ownership
    chown -R "${CONTAINER_USER}":"${CONTAINER_USER}" "$HOOK_DIRECTORIES/pre-startup" "$HOOK_DIRECTORIES/startup"
    echo "✓ Hook scripts copied and permissions set"
else
    echo "! Hook scripts source directory /tmp/installers/hooks not found, skipping hook setup"
fi

# Make everything in PROTON_PATH executable and set ownership
echo "Setting permissions and ownership for ${PROTON_PATH}..."
chmod -R +x "$PROTON_PATH"
chown -R "${CONTAINER_USER}":"${CONTAINER_USER}" "$PROTON_PATH"
echo "✓ Permissions and ownership set for ${PROTON_PATH}"


echo "Proton GE installation complete!"
echo "    Requested Version: ${PROTON_VERSION}"
echo "    Installed Tag: ${PROTON_TAG_NAME}"
echo "    Path: ${PROTON_PATH}"
echo "    Prefix: ${WINEPREFIX}"
echo "    i386 Support: ${INSTALL_I386}"

# Re-source environment for current script - useful for interactive sessions
# Note: This does not affect the environment of the calling script/Dockerfile RUN instruction
# echo "Re-sourcing /etc/environment..."
# . /etc/environment

exit 0
