#!/bin/bash
# Wine installation script for Docker SteamCMD Server
# Handles version-specific differences in Wine packaging
#
# This script handles Wine installation with specific logic for:
# - Wine versions < 10.2 (using wine64/win64)
# - Wine versions >= 10.2 (using wow64)
# - ARM64 vs AMD64 architectures
# - 32-bit (i386) support

set -eo pipefail

# Load environment variables if present
if [ -f /etc/environment ]; then
    . /etc/environment
fi

echo "Starting Wine Installation..."

# Verify required parameters are provided
if [ -z "$TARGETARCH" ]; then
    echo "✗ ERROR: TARGETARCH is required but not set"
    exit 1
fi

# Get parameters from environment
WINE_PATH="/opt/wine-${WINE_BRANCH}/bin"
WINEPREFIX="/home/$CONTAINER_USER/app/Wine"

# ===== Package Variables =====
# These can be overridden by setting environment variables before calling the script

PACKAGES_WINE="\
    `# Fake X-Server desktop for Wine`
    xvfb \
    `# xauth needed with --no-install-recommends with wine`
    xauth \
    `# Font configuration needed by many Windows applications`
    fontconfig \
    `# Libraries frequently needed by Windows applications`
    libfreetype6 \
    libpng16-16 \
    libjpeg62-turbo"

PACKAGES_WINE_I386="\
    `# 32-bit libraries needed for i386 Wine`
    libfreetype6:i386 \
    libpng16-16:i386 \
    libjpeg62-turbo:i386 \
    `# Additional dependencies for 32-bit applications`
    libglib2.0-0:i386 \
    libgstreamer1.0-0:i386"

# Log configuration
echo "Wine Configuration:"
echo "  Version: ${WINE_VERSION}"
echo "  Branch: ${WINE_BRANCH}"
echo "  Target Architecture: ${TARGETARCH}"
echo "  Install i386 support: ${INSTALL_I386}"

# ===== Step 1: Determine Wine architecture and executable =====
echo "Step 1: Determining Wine architecture and executable..."

# Get major.minor version numbers for comparison
WINE_VER_MAJOR=$(echo "$WINE_VERSION" | cut -d. -f1)
WINE_VER_MINOR=$(echo "$WINE_VERSION" | cut -d. -f2)

# Determine WINEARCH and WINE_EXECUTABLE based on Wine version
if [ "$WINE_VER_MAJOR" -gt 10 ] || ([ "$WINE_VER_MAJOR" -eq 10 ] && [ "$WINE_VER_MINOR" -ge 2 ]); then
    echo "✓ Wine version >= 10.2, using wow64 architecture"
    WINEARCH="wow64"
    WINE_EXECUTABLE="wine"
else
    echo "✓ Wine version < 10.2, using win64 architecture"
    WINEARCH="win64"
    WINE_EXECUTABLE="wine64"
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
echo "Step 3: Installing Wine packages..."

# Install Wine packages
apt-get install -y --no-install-recommends $PACKAGES_WINE

# Install i386 packages if requested
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    apt-get install -y --no-install-recommends $PACKAGES_WINE_I386
    echo "✓ Wine i386 packages installed"
fi

# ===== Step 4: Setup environment variables =====
echo "Step 4: Setting up environment variables..."

# Update environment file with Wine configurations
cat << EOT >> /etc/environment

# Wine configuration values set by installer script
export WINE_PATH=${WINE_PATH}
export WINEPREFIX=${WINEPREFIX}
export WINEARCH=${WINEARCH}
export WINEDEBUG=fixme-all

# Wine log configuration
export WINE_LOG=1
export WINE_TRACE_FILE=/var/log/wine.log
EOT

# Update the APP_COMMAND_PREFIX for wine, using WINE_EXECUTABLE
if grep -q "APP_COMMAND_PREFIX" /etc/environment; then
    # If already set (possibly by box64 script), append $WINE_EXECUTABLE to it
    OLD_PREFIX=$(grep "APP_COMMAND_PREFIX" /etc/environment | cut -d= -f2 | tr -d '"')
    if [ -z "$OLD_PREFIX" ]; then
        sed -i "s/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX=\"$WINE_EXECUTABLE\"/" /etc/environment
    else
        # Check if $WINE_EXECUTABLE is already in the prefix to avoid duplication
        if [[ "$OLD_PREFIX" != *"$WINE_EXECUTABLE"* ]]; then
            # Create the new prefix without adding extra quotes
            NEW_PREFIX="$OLD_PREFIX $WINE_EXECUTABLE"
            sed -i "s/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX=\"$NEW_PREFIX\"/" /etc/environment
        fi
    fi
else
    # If not set, create a new entry
    echo "export APP_COMMAND_PREFIX=\"$WINE_EXECUTABLE\"" >> /etc/environment
fi

# ===== Step 5: Create required directories =====
echo "Step 5: Creating required directories..."
mkdir -p "$WINE_PATH" "$WINEPREFIX" /tmp/wine_debs

# ===== Step 6: Download and install Wine packages =====
echo "Step 6: Downloading and installing Wine packages..."

TEMP_DIR="/tmp/wine_debs"
WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/"
WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/"

# Define package names
WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"
WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"

# Define i386 package names
WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"
WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"

echo "Downloading Wine 64-bit packages..."

# Download the 64-bit packages
curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}"
curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}"

# Install the 64-bit packages
dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" /
dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" /
echo "✓ Wine 64-bit packages installed"
echo "✓ Wine 64-bit packages installed"

# Install i386 support if requested
# NOTE not sure if i386 is needed
if [ "$INSTALL_I386" = "true" ]; then
    echo "Downloading Wine 32-bit packages..."
    
    # Download the 32-bit packages
    curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}"
    curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}"
    
    # Install the 32-bit packages
    dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" /
    dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" /
    
    echo "✓ Wine 32-bit packages installed"
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

# ===== Step 7: Create symlinks =====
echo "Step 7: Setting up Wine symlinks..."

# Create direct symlinks for the main wine executable
ln -sf "$WINE_PATH/$WINE_EXECUTABLE" /usr/local/bin/$WINE_EXECUTABLE

# Add wine32 symlink if i386 support is installed
# NOTE not sure if i386 is needed
if [ "$INSTALL_I386" = "true" ] && [ -f "$WINE_PATH/wine32" ]; then
    ln -sf "$WINE_PATH/wine32" /usr/local/bin/wine32
fi

# Common symlinks for all architectures and versions
ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot
ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg
ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver

# hooks
mkdir -p $HOOK_DIRECTORIES/pre-startup $HOOK_DIRECTORIES/startup
cp /tmp/installers/hooks/pre-startup/20_wine_prefix.sh $HOOK_DIRECTORIES/pre-startup/20_wine_prefix.sh
cp /tmp/installers/hooks/startup/10_xvfb_wine.sh $HOOK_DIRECTORIES/startup/10_xvfb_wine.sh
chown -R ${CONTAINER_USER}:${CONTAINER_USER} $HOOK_DIRECTORIES/pre-startup $HOOK_DIRECTORIES/startup

# Make everything executable
chown -R ${CONTAINER_USER}:${CONTAINER_USER} $WINE_PATH
chmod +x \
    "$WINE_PATH/$WINE_EXECUTABLE" \
    "$WINE_PATH/wineboot" \
    "$WINE_PATH/winecfg" \
    "$WINE_PATH/wineserver"

echo "Wine installation complete!"
echo "  WINEARCH: ${WINEARCH}"
echo "  WINE_PATH: ${WINE_PATH}"
echo "  WINEPREFIX: ${WINEPREFIX}"
echo "  i386 Support: ${INSTALL_I386}"

# Re-source environment for current script
. /etc/environment

exit 0