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
echo "------------------------------------------------------- WINE INSTALLATION SCRIPT -----------------------------------------------------------------------"

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
echo "  Distribution: ${WINE_DIST}"
echo "  Tag: ${WINE_TAG}"
echo "  Target Architecture: ${TARGETARCH}"
echo "  Install i386 support: ${INSTALL_I386}"
echo "  Wine Packages: ${PACKAGES_WINE}"
echo "  Wine i386 Packages: ${PACKAGES_WINE_I386}"

# ===== Step 1: Determine Wine architecture and executable =====
echo "Determining Wine architecture and executable..."

# Get major.minor version numbers for comparison
WINE_VER_MAJOR=$(echo "$WINE_VERSION" | cut -d. -f1)
WINE_VER_MINOR=$(echo "$WINE_VERSION" | cut -d. -f2)

# Determine WINEARCH and WINE_EXECUTABLE based on Wine version
if [ "$WINE_VER_MAJOR" -gt 10 ] || ([ "$WINE_VER_MAJOR" -eq 10 ] && [ "$WINE_VER_MINOR" -ge 2 ]); then
    echo "✓ Wine version >= 10.2, using wow64 architecture"
    WINEARCH="wow64"
    WINE_EXECUTABLE="wine"
    
    # Check for potential conflicts with i386 support on newer Wine versions
    if [ "$INSTALL_I386" = "true" ]; then
        echo "! Note: i386 support for Wine >= 10.2 may have compatibility issues with the wow64 architecture"
        echo "! Proceeding with installation, but consider testing carefully"
    fi
else
    echo "✓ Wine version < 10.2, using win64 architecture"
    WINEARCH="win64"
    WINE_EXECUTABLE="wine64"
fi

# ===== Step 2: Set up architecture support =====
echo "Setting up architecture support..."

# Add i386 architecture if requested and not on ARM
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    echo "Adding i386 architecture support..."
    dpkg --add-architecture i386 || { 
        echo "✗ ERROR: Failed to add i386 architecture"
        exit 1
    }
    apt-get update || { 
        echo "✗ ERROR: Failed to update package lists"
        exit 1
    }
    echo "✓ i386 architecture support added"
else
    echo "✓ Skipping i386 architecture setup"
fi

# ===== Step 3: Install base packages =====
echo "Installing Wine packages..."

# Install Wine packages
echo "Installing Wine packages: $PACKAGES_WINE"
apt-get install -y --no-install-recommends $PACKAGES_WINE || {
    echo "✗ ERROR: Failed to install Wine packages"
    exit 1
}
echo "✓ Wine packages installed successfully"

# Install i386 packages if requested
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    echo "Installing Wine i386 packages: $PACKAGES_WINE_I386"
    apt-get install -y --no-install-recommends $PACKAGES_WINE_I386 || {
        echo "✗ ERROR: Failed to install Wine i386 packages"
        exit 1
    }
    echo "✓ Wine i386 packages installed successfully"
fi

# ===== Step 4: Setup environment variables =====
echo "Setting up environment variables..."

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
            sed -i "s/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX=\"'$OLD_PREFIX' $WINE_EXECUTABLE\"/" /etc/environment
        fi
    fi
else
    # If not set, create a new entry
    echo "export APP_COMMAND_PREFIX=\"$WINE_EXECUTABLE\"" >> /etc/environment
fi

# ===== Step 5: Create required directories =====
echo "Creating required directories..."
mkdir -p "$WINE_PATH" "$WINEPREFIX" /tmp/wine_debs

# ===== Step 6: Download and install Wine packages =====
echo "Downloading and installing Wine packages..."

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
curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}" || {
    echo "✗ ERROR: Failed to download Wine 64-bit main package"
    exit 1
}
curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" || {
    echo "✗ ERROR: Failed to download Wine 64-bit support package"
    exit 1
}

# Install the 64-bit packages
echo "Installing Wine 64-bit packages..."
dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" / || {
    echo "✗ ERROR: Failed to extract Wine 64-bit main package"
    exit 1
}
dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" / || {
    echo "✗ ERROR: Failed to extract Wine 64-bit support package"
    exit 1
}
echo "✓ Wine 64-bit packages installed successfully"

# Install i386 support if requested
if [ "$INSTALL_I386" = "true" ]; then
    if [ "$TARGETARCH" = "arm64" ]; then
        echo "! Warning: i386 support not fully compatible with ARM64 architecture"
        echo "! Some i386 Wine components may not function correctly"
    fi
    
    echo "Downloading Wine 32-bit packages:"
    echo "  ${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}"
    echo "  ${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}"
    
    # Download the 32-bit packages
    curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}" || {
        echo "✗ ERROR: Failed to download Wine 32-bit main package"
        exit 1
    }
    curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" || {
        echo "✗ ERROR: Failed to download Wine 32-bit support package"
        exit 1
    }
    
    # Install the 32-bit packages
    echo "Installing Wine 32-bit packages..."
    dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" / || {
        echo "✗ ERROR: Failed to extract Wine 32-bit main package"
        exit 1
    }
    dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" / || {
        echo "✗ ERROR: Failed to extract Wine 32-bit support package"
        exit 1
    }
    
    echo "✓ Wine 32-bit packages installed successfully"
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

# ===== Step 7: Create symlinks and wrappers =====
echo "Setting up Wine symlinks and wrappers..."

if [ "$TARGETARCH" = "arm64" ]; then
    # For ARM64, check if box64 is available
    if command -v box64 >/dev/null 2>&1; then
        echo "Creating ARM64-specific wine wrapper using box64"
        cat > /usr/local/bin/wine << EOF
#!/bin/bash
box64 $WINE_PATH/$WINE_EXECUTABLE "\$@"
EOF
        chmod +x /usr/local/bin/wine
        echo "✓ ARM64 wine wrapper created with box64"
    else
        echo "✗ ERROR: box64 is required for Wine on ARM64 but was not found"
        exit 1
    fi
    
    # Add additional wrapper for wine32 if i386 support is installed
    if [ "$INSTALL_I386" = "true" ]; then
        # Check if box86 is available
        if command -v box86 >/dev/null 2>&1; then
            echo "Creating ARM64-specific wine32 wrapper using box86"
            cat > /usr/local/bin/wine32 << EOF
#!/bin/bash
box86 $WINE_PATH/$WINE_EXECUTABLE "\$@"
EOF
            chmod +x /usr/local/bin/wine32
            echo "✓ ARM64 wine32 wrapper created with box86"
        else
            echo "! Warning: box86 is required for 32-bit Wine on ARM64 but was not found"
            echo "! 32-bit Wine support will not be available"
        fi
    fi
else
    # For AMD64, create direct symlinks
    echo "Creating AMD64 wine symlinks"
    #NOTE creating a symlink with a name 'wine' for 'wine64' can confuse wine internal logic
    ln -sf "$WINE_PATH/$WINE_EXECUTABLE" /usr/local/bin/$WINE_EXECUTABLE || {
        echo "✗ ERROR: Failed to create wine symlink"
        exit 1
    }
    echo "✓ AMD64 wine symlink created"

    # Add wine32 symlink if i386 support is installed
    if [ "$INSTALL_I386" = "true" ] && [ -f "$WINE_PATH/wine32" ]; then
        ln -sf "$WINE_PATH/wine32" /usr/local/bin/wine32 || {
            echo "! Warning: Failed to create wine32 symlink"
        }
        echo "✓ AMD64 wine32 symlink created"
    fi
fi

# hooks
mkdir -p $HOOK_DIRECTORIES/pre-startup $HOOK_DIRECTORIES/startup
cp /tmp/installers/hooks/pre-startup/20_wine_prefix.sh $HOOK_DIRECTORIES/pre-startup/20_wine_prefix.sh
cp /tmp/installers/hooks/startup/10_xvfb_wine.sh $HOOK_DIRECTORIES/startup/10_xvfb_wine.sh
chown -R ${CONTAINER_USER}:${CONTAINER_USER} $HOOK_DIRECTORIES/pre-startup $HOOK_DIRECTORIES/startup

# Common symlinks for all architectures and versions
ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot || {
    echo "! Warning: Failed to create wineboot symlink"
}
ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg || {
    echo "! Warning: Failed to create winecfg symlink"
}
ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver || {
    echo "! Warning: Failed to create wineserver symlink"
}

# Make everything executable
chown -R ${CONTAINER_USER}:${CONTAINER_USER} $WINE_PATH
chmod +x \
    "$SCRIPTS/$WINE_EXECUTABLE" \
    "$WINE_PATH/wineboot" \
    "$WINE_PATH/winecfg" \
    "$WINE_PATH/wineserver" || {
    echo "! Warning: Failed to set executable permissions on some Wine binaries"
}

# ===== Step 8: Tests ==========================================
# FIXME for same reasons as boxes.sh, QEMU blocks box86 arm runs, x86 works. 
# echo "Running verification tests..."

# # Test Wine installation
# if command -v wine >/dev/null 2>&1; then
#     echo "✓ Wine command found"
#     # Capture wine version output to a file
#     wine --version > /tmp/wine_version.txt || { 
#         echo "✗ ERROR: Wine version command failed"
#         exit 1
#     }
#     echo "✓ Wine version: $(cat /tmp/wine_version.txt)"
# else
#     echo "✗ ERROR: Wine installation failed - command not found"
#     exit 1
# fi

# # Test Wine32 installation if i386 support is installed
# if [ "$INSTALL_I386" = "true" ] && [ -f "/usr/local/bin/wine32" ]; then
#     if command -v wine32 >/dev/null 2>&1; then
#         echo "✓ Wine32 command found"
#     else
#         echo "! Warning: Wine32 command not found despite i386 support being enabled"
#     fi
# fi

# echo "✓ All installation tests passed successfully!"

echo "Wine installation complete!"
echo "  WINEARCH: ${WINEARCH}"
echo "  WINE_PATH: ${WINE_PATH}"
echo "  WINEPREFIX: ${WINEPREFIX}"
echo "  i386 Support: ${INSTALL_I386}"

# Re-source environment for current script
. /etc/environment

# Show final environment configuration
echo "Final environment configuration:"
cat /etc/environment

exit 0
