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

# Display header
echo "------------------------------------------------------- WINE INSTALLATION SCRIPT -----------------------------------------------------------------------" && \

# Get parameters from environment or use defaults
WINE_VERSION="${WINE_VERSION:-10.5}"
WINE_BRANCH="${WINE_BRANCH:-staging}"
WINE_ID="${WINE_ID:-debian}"
WINE_DIST="${WINE_DIST:-bookworm}"
WINE_TAG="${WINE_TAG:--1}"
WINE_PATH="/opt/wine-${WINE_BRANCH}/bin"
WINEPREFIX="${WINEPREFIX:-/home/$CONTAINER_USER/app/Wine}"
TARGETARCH="${TARGETARCH:-amd64}"
# Flag to control i386 installation
INSTALL_I386="${INSTALL_I386:-false}"

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
echo "  Distribution: ${WINE_DIST}"
echo "  Tag: ${WINE_TAG}"
echo "  Target Architecture: ${TARGETARCH}"
echo "  Install i386 support: ${INSTALL_I386}"
echo "  Wine Packages: ${PACKAGES_WINE}"
echo "  Wine i386 Packages: ${PACKAGES_WINE_I386}"

# Get major.minor version numbers for comparison
WINE_VER_MAJOR=$(echo "$WINE_VERSION" | cut -d. -f1)
WINE_VER_MINOR=$(echo "$WINE_VERSION" | cut -d. -f2)

# Determine WINEARCH and WINE_EXECUTABLE based on Wine version
if [ "$WINE_VER_MAJOR" -gt 10 ] || ([ "$WINE_VER_MAJOR" -eq 10 ] && [ "$WINE_VER_MINOR" -ge 2 ]); then
    echo "Wine version >= 10.2, using wow64 architecture"
    WINEARCH="wow64"
    WINE_EXECUTABLE="wine"
    
    # Check for potential conflicts with i386 support on newer Wine versions
    if [ "$INSTALL_I386" = "true" ]; then
        echo "Note: i386 support for Wine >= 10.2 may have compatibility issues with the wow64 architecture"
        echo "      Proceeding with installation, but consider testing carefully"
    fi
else
    echo "Wine version < 10.2, using win64 architecture"
    WINEARCH="win64"
    WINE_EXECUTABLE="wine64"
fi
# Add i386 architecture if requested and not on ARM
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    echo "Adding i386 architecture support..."
    dpkg --add-architecture i386 || echo "i386 architecture already added or not supported"
    apt-get update
fi

# Install Wine packages
echo "Installing Wine packages: $PACKAGES_WINE"
apt-get install -y --no-install-recommends $PACKAGES_WINE

# Install i386 packages if requested
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    echo "Installing Wine i386 packages: $PACKAGES_WINE_I386"
    apt-get install -y --no-install-recommends $PACKAGES_WINE_I386
fi

# Update environment file with Wine configurations
echo "" >> /etc/environment
echo "# Wine configuration values set by installer script" >> /etc/environment
echo "WINE_PATH=${WINE_PATH}" >> /etc/environment
echo "WINEPREFIX=${WINEPREFIX}" >> /etc/environment
echo "WINEARCH=${WINEARCH}" >> /etc/environment
echo "WINEDEBUG=fixme-all" >> /etc/environment

# Update the APP_COMMAND_PREFIX for wine
if grep -q "APP_COMMAND_PREFIX" /etc/environment; then
    # If already set (possibly by box64 script), append wine to it
    OLD_PREFIX=$(grep "APP_COMMAND_PREFIX" /etc/environment | cut -d= -f2 | tr -d '"')
    if [ -z "$OLD_PREFIX" ]; then
        sed -i 's/^APP_COMMAND_PREFIX=.*/APP_COMMAND_PREFIX="wine"/' /etc/environment
    else
        sed -i 's/^APP_COMMAND_PREFIX=.*/APP_COMMAND_PREFIX="'"$OLD_PREFIX"' wine"/' /etc/environment
    fi
else
    # If not set, create a new entry
    echo 'APP_COMMAND_PREFIX="wine"' >> /etc/environment
fi

# Create required directories
mkdir -p "$WINE_PATH" "$WINEPREFIX" /tmp/wine_debs

# Download and install Wine packages
TEMP_DIR="/tmp/wine_debs"
WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/"
WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/"

# Define package names
WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"
WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"

# Define i386 package names
WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"
WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"

echo "Downloading Wine 64-bit packages:"
echo "  ${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}"
echo "  ${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}"

# Download the 64-bit packages
curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}"
curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}"

# Install the 64-bit packages
echo "Installing Wine 64-bit packages..."
dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" /
dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" /

# Install i386 support if requested
if [ "$INSTALL_I386" = "true" ]; then
    if [ "$TARGETARCH" = "arm64" ]; then
        echo "Warning: i386 support not fully compatible with ARM64 architecture"
        echo "         Some i386 Wine components may not function correctly"
    fi
    
    echo "Downloading Wine 32-bit packages:"
    echo "  ${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}"
    echo "  ${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}"
    
    # Download the 32-bit packages
    curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}"
    curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}"
    
    # Install the 32-bit packages
    echo "Installing Wine 32-bit packages..."
    dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" /
    dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" /
    
    echo "32-bit Wine support installed"
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

# Create symlinks based on architecture
echo "Setting up Wine symlinks..."

if [ "$TARGETARCH" = "arm64" ]; then
    # For ARM64, create a wrapper script that uses box64
    echo "Creating ARM64-specific wine wrapper using box64"
    cat > /usr/local/bin/wine << EOF
#!/bin/bash
box64 $WINE_PATH/$WINE_EXECUTABLE "\$@"
EOF
chmod +x /usr/local/bin/wine
EOF
    chmod +x /usr/local/bin/wine
    
    # Add additional wrapper for wine32 if i386 support is installed
    if [ "$INSTALL_I386" = "true" ]; then
        echo "Creating ARM64-specific wine32 wrapper using box86"
        cat > /usr/local/bin/wine32 << 'EOF'
#!/bin/bash
box86 $WINE_PATH/wine "$@"
EOF
        chmod +x /usr/local/bin/wine32
    fi
else
    # For AMD64, create direct symlinks
    echo "Creating AMD64 wine symlinks"
    ln -sf "$WINE_PATH/$WINE_EXECUTABLE" /usr/local/bin/wine

    # Add wine32 symlink if i386 support is installed
    if [ "$INSTALL_I386" = "true" ] && [ -f "$WINE_PATH/wine32" ]; then
        ln -sf "$WINE_PATH/wine32" /usr/local/bin/wine32
    fi
fi

# Common symlinks for all architectures and versions
ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot
ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg
ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver

# Make everything executable
chmod +x \
    /usr/local/bin/wine \
    "$WINE_PATH/wineboot" \
    "$WINE_PATH/winecfg" \
    "$WINE_PATH/wineserver"

echo "Wine installation complete!"
echo "  WINEARCH: ${WINEARCH}"
echo "  WINE_PATH: ${WINE_PATH}"
echo "  WINEPREFIX: ${WINEPREFIX}"
echo "  i386 Support: ${INSTALL_I386}"

exit 0
