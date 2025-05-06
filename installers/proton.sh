#!/bin/bash
# Proton GE installation script for Docker SteamCMD Server
# Handles installation of Proton GE (Glorious Eggroll's custom Proton build)
# Reference: https://github.com/GloriousEggroll/proton-ge-custom?tab=readme-ov-file#native
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
[ -f /etc/environment ] && . /etc/environment

echo "Starting Proton GE Installation..."

# Verify required parameters
[ -z "$TARGETARCH" ] && { echo "✗ ERROR: TARGETARCH is required but not set"; exit 1; }
[ -z "$PROTON_VERSION" ] && { echo "✗ ERROR: PROTON_VERSION is required but not set. Please provide the base version (e.g., '8.0-5')."; exit 1; }

# Get parameters from environment or use defaults
PROTON_PATH="${PROTON_PATH:-/opt/proton}"
WINEPREFIX="${WINEPREFIX:-/home/$CONTAINER_USER/app/Proton}"
INSTALL_I386="${INSTALL_I386:-true}"
CONTAINER_USER="${CONTAINER_USER:-steam}"
HOOK_DIRECTORIES="${HOOK_DIRECTORIES:-/opt/steam/hooks}"

# Construct the full Proton GE tag name
VERSION_CLEANED="${PROTON_VERSION#GE-}"
VERSION_CLEANED="${VERSION_CLEANED#Proton}"
VERSION_CLEANED="${VERSION_CLEANED#-}"
VERSION_FORMATTED="${VERSION_CLEANED//./-}"
PROTON_TAG_NAME="GE-Proton${VERSION_FORMATTED}"

# Log configuration
echo "Proton GE Configuration:"
echo "    Version: ${PROTON_VERSION} (Tag: ${PROTON_TAG_NAME})"
echo "    Architecture: ${TARGETARCH} (i386 support: ${INSTALL_I386})"
echo "    Path: ${PROTON_PATH}, Prefix: ${WINEPREFIX}"

# ===== Package Variables =====
PACKAGES_PROTON="\
    `# Fake X-Server desktop for Wine/Proton - needed for server`
    xvfb \
    `# xauth needed with --no-install-recommends with wine`
    xauth \
    `# Font configuration needed by many Windows applications`
    fontconfig \
    `# Required by proton`
    python3 \
    `# Libraries frequently needed by Windows applications`
    libfreetype6 \
    libpng16-16 \
    libjpeg62-turbo \
    libglib2.0-0 \
    libdbus-1-3 \
    libnss3 \
    libx11-6"

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

# ===== Step 1: Check for Box86/Box64 on ARM64 =====
echo "Step 1: Checking system compatibility..."

if [ "$TARGETARCH" = "arm64" ]; then
    command -v box64 >/dev/null 2>&1 || { echo "✗ ERROR: box64 is required for Proton on ARM64"; exit 1; }
    
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
fi

# ===== Step 3: Install base packages =====
echo "Step 3: Installing Proton dependencies..."

# Install base packages
apt-get install -y --no-install-recommends $PACKAGES_PROTON

# Install i386 packages if requested and not on ARM
[ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ] && \
    apt-get install -y --no-install-recommends $PACKAGES_PROTON_I386

# ===== Step 4: Setup environment variables =====
echo "Step 4: Setting up environment variables..."

# Add Proton configuration to environment file
tee -a /etc/environment > /dev/null << EOT

# Proton GE configuration
export PROTON_PATH=${PROTON_PATH}
export PROTON_VERSION=${PROTON_VERSION}
export WINEPREFIX=${WINEPREFIX}
export WINEDEBUG=fixme-all

# Proton-specific environment variables
export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAMCMD_PATH}
export STEAM_COMPAT_DATA_PATH=${WINEPREFIX}

# Enable Steam Play debug logging
export PROTON_LOG=1
export PROTON_LOG_DIR=${LOGS}
EOT

# Update APP_COMMAND_PREFIX for Proton
if grep -q "export APP_COMMAND_PREFIX=" /etc/environment; then
    # If already set, append proton run to it
    sed -i '/export APP_COMMAND_PREFIX=/ {
        s/export APP_COMMAND_PREFIX="\(.*\)"/export APP_COMMAND_PREFIX="\1 proton runinprefix"/
        t # jump to end if substitution was made
        s/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX="proton runinprefix"/ # handle case without quotes
    }' /etc/environment
else
    # If not set, create a new entry
    echo 'export APP_COMMAND_PREFIX="proton runinprefix"' >> /etc/environment
fi

# ===== Step 5: Create required directories =====
echo "Step 5: Creating required directories..."
mkdir -p "${PROTON_PATH}" "${WINEPREFIX}" "/var/log/proton"

# ===== Step 6: Download and install Proton GE =====
echo "Step 6: Downloading and installing Proton GE..."

# Define download URL for Proton GE using the constructed tag name
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_TAG_NAME}/${PROTON_TAG_NAME}.tar.gz"

mkdir -p /tmp/proton_ge
curl -sL "$PROTON_URL" -o /tmp/proton_ge/proton.tar.gz || { 
    echo "✗ ERROR: Failed to download Proton GE from ${PROTON_URL}"; 
    rm -rf /tmp/proton_ge; 
    exit 1; 
}

tar -xzf /tmp/proton_ge/proton.tar.gz -C /tmp/proton_ge || { 
    echo "✗ ERROR: Failed to extract Proton GE archive"; 
    rm -rf /tmp/proton_ge; 
    exit 1; 
}

mv /tmp/proton_ge/${PROTON_TAG_NAME}/* "${PROTON_PATH}/"
rm -rf /tmp/proton_ge

# Generate machine-id for Proton
rm -f /etc/machine-id
python3 -c 'import uuid; print(uuid.uuid4())' > /etc/machine-id

# Verify installation
[ -f "${PROTON_PATH}/proton" ] || {
    echo "✗ ERROR: Proton GE installation failed. proton executable not found.";
    ls -la "${PROTON_PATH}";
    exit 1;
}

# ===== Step 7: Create proton wrapper script =====
echo "Step 7: Setting up Proton wrapper..."

# Create a wrapper script to handle path resolution problems
cat > /usr/local/bin/proton << EOF
#!/bin/bash
# Wrapper script to correctly call Proton with proper path resolution
exec "${PROTON_PATH}/proton" "\$@"
EOF
chmod +x /usr/local/bin/proton

# Setup for ARM64 - additional wrappers if needed
if [ "$TARGETARCH" = "arm64" ]; then
    if command -v box64 >/dev/null 2>&1; then
        # Modify the wrapper to use box64
        cat > /usr/local/bin/proton << EOF
#!/bin/bash
# Wrapper script to run proton via box64
exec box64 "${PROTON_PATH}/proton" "\$@"
EOF
        chmod +x /usr/local/bin/proton
        
        # Create wrappers for wine components if needed
        if [ "$INSTALL_I386" = "true" ] && command -v box86 >/dev/null 2>&1; then
            cat > /usr/local/bin/proton-wine << EOF
#!/bin/bash
# Wrapper script to run wine via box86
exec box86 "${PROTON_PATH}/files/bin/wine" "\$@"
EOF
            chmod +x /usr/local/bin/proton-wine
        fi
    fi
fi

# ===== Step 8: Setup hooks =====
echo "Step 8: Setting up hooks..."

# Create hooks directories if they don't exist
mkdir -p "$HOOK_DIRECTORIES/pre-startup" "$HOOK_DIRECTORIES/startup"

# Copy hook scripts if they exist
if [ -d "/tmp/installers/hooks" ]; then
    cp -f /tmp/installers/hooks/pre-startup/20_proton_prefix.sh "$HOOK_DIRECTORIES/pre-startup/20_proton_prefix.sh" 2>/dev/null || echo "! Hook script 20_proton_prefix.sh not found"
    cp -f /tmp/installers/hooks/startup/10_xvfb_proton.sh "$HOOK_DIRECTORIES/startup/10_xvfb_proton.sh" 2>/dev/null || echo "! Hook script 10_xvfb_proton.sh not found"
    chown -R "${CONTAINER_USER}":"${CONTAINER_USER}" "$HOOK_DIRECTORIES/pre-startup" "$HOOK_DIRECTORIES/startup"
fi

# Set permissions and ownership for Proton path
chmod -R +x "$PROTON_PATH"
chown -R "${CONTAINER_USER}":"${CONTAINER_USER}" "$PROTON_PATH"

echo "Proton GE installation complete! (Version: ${PROTON_TAG_NAME})"

exit 0
