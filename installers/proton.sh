#!/bin/bash
# Proton installation script for Docker SteamCMD Server
# Handles installation of Proton (Valve's compatibility tool based on Wine)
#
# This script installs:
# - Proton from GitHub releases
# - Required dependencies for Proton
# - Configures environment variables for Proton

set -eo pipefail

# Load environment variables if present
if [ -f /etc/environment ]; then
    . /etc/environment
fi

# Display header
echo "------------------------------------------------------- Proton Compatibility Layer Setup --------------------------------------------------------------------"

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
    `# Graphics-related dependencies`
    libvulkan1 \
    mesa-vulkan-drivers \
    `# Font configuration needed by many games`
    fontconfig \
    `# Common libraries needed by games`
    libfreetype6 \
    libpng16-16 \
    libjpeg62-turbo \
    `# Audio support`
    libasound2 \
    `# Common dependencies for Steam and Proton`
    libglib2.0-0 \
    libdbus-1-3 \
    `# Additional libraries commonly needed`
    libnss3 \
    libx11-6 \
    libxss1 \
    libegl1"

# Additional i386 packages needed for 32-bit game support
PACKAGES_PROTON_I386="\
    `# 32-bit graphics libraries`
    libvulkan1:i386 \
    mesa-vulkan-drivers:i386 \
    `# 32-bit common libraries`
    libfreetype6:i386 \
    libpng16-16:i386 \
    libjpeg62-turbo:i386 \
    `# 32-bit audio support`
    libasound2:i386 \
    `# 32-bit common dependencies`
    libglib2.0-0:i386 \
    libdbus-1-3:i386 \
    `# 32-bit additional libraries`
    libnss3:i386 \
    libx11-6:i386 \
    libxss1:i386 \
    libegl1:i386"

# Flag to control i386 installation

# Log configuration
echo "Proton Configuration:"
echo "  Proton Version: ${PROTON_VERSION}"
echo "  Proton Path: ${PROTON_PATH}"
echo "  Target Architecture: ${TARGETARCH}"
echo "  Install i386 support: ${INSTALL_I386}"
echo "  Proton Packages: ${PACKAGES_PROTON}"

# ===== Step 1: Check for Box86/Box64 on ARM64 =====
if [ "$TARGETARCH" = "arm64" ]; then
    # Check if box64 is installed
    if ! command -v box64 >/dev/null 2>&1; then
        echo "✗ ERROR: box64 is not installed but required for Proton on ARM64"
        exit 1
    else
        echo "✓ box64 is installed"
    fi
    
    # Check for box86 if i386 support is requested
    if [ "$INSTALL_I386" = "true" ]; then
        if ! command -v box86 >/dev/null 2>&1; then
            echo "! Warning: box86 is not installed. Disabling i386 support on ARM64."
            INSTALL_I386="false"
        else
            echo "✓ box86 is installed"
        fi
    fi
fi

# ===== Step 2: Setup environment variables =====
echo "Setting up environment variables..."

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
    # Get existing prefix, if any
    EXISTING_PREFIX=$(grep "APP_COMMAND_PREFIX" /etc/environment | cut -d= -f2 | tr -d '"')
    
    if [ -z "$EXISTING_PREFIX" ]; then
        # If prefix exists but is empty, set it to proton run
        sed -i 's/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX="proton run"/' /etc/environment
    else
        # Check if proton run is already in the prefix to avoid duplication
        if [[ "$EXISTING_PREFIX" != *"proton run"* ]]; then
            # If prefix exists, append proton run
            sed -i 's/export APP_COMMAND_PREFIX=.*/export APP_COMMAND_PREFIX="'"$EXISTING_PREFIX"' proton run"/' /etc/environment
        fi
    fi
else
    # If no prefix exists, create one with proton run
    echo 'export APP_COMMAND_PREFIX="proton run"' >> /etc/environment
fi

# ===== Step 3: Setup architecture support =====
echo "Setting up architecture support..."

# Add i386 architecture if requested
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    echo "Adding i386 architecture support..."
    dpkg --add-architecture i386
    apt-get update
fi

# ===== Step 4: Install base packages =====
echo "Installing Proton dependencies..."

# Install base packages
echo "Installing Proton packages: $PACKAGES_PROTON"
apt-get install -y --no-install-recommends $PACKAGES_PROTON

# Install i386 packages if requested
if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" != "arm64" ]; then
    echo "Installing Proton i386 packages: $PACKAGES_PROTON_I386"
    apt-get install -y --no-install-recommends $PACKAGES_PROTON_I386
fi

# ===== Step 5: Create required directories =====
echo "Creating required directories..."
mkdir -p "${PROTON_PATH}" "${WINEPREFIX}" "/var/log/proton/crash_reports"

# ===== Step 6: Download and install Proton =====
if [ -n "$PROTON_VERSION" ]; then
    echo "Downloading Proton ${PROTON_VERSION}..."
    
    # Define download URL
    PROTON_URL="https://github.com/ValveSoftware/Proton/releases/download/proton-${PROTON_VERSION}/proton-${PROTON_VERSION}.tar.gz"
    
    echo "Download URL: ${PROTON_URL}"
    curl -sL "$PROTON_URL" -o /tmp/proton.tar.gz
    
    # Extract Proton
    echo "Extracting Proton to ${PROTON_PATH}..."
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

# ===== Step 7: Create helper scripts and wrappers =====
echo "Creating Proton helper scripts..."

# Create a wrapper script for proton
cat > /usr/local/bin/proton << EOF
#!/bin/bash
# Proton wrapper script
PROTON_BINARY="\${PROTON_PATH}/proton"

# Check if valid command
if [[ "\$1" == "run" ]]; then
    # Run a Windows executable through Proton
    shift
    exec "\$PROTON_BINARY" run "\$@"
elif [[ "\$1" == "waitforexitandrun" ]]; then
    # Wait for a process to finish and then run
    shift
    exec "\$PROTON_BINARY" waitforexitandrun "\$@"
else
    # Just pass all arguments to Proton
    exec "\$PROTON_BINARY" "\$@"
fi
EOF

chmod +x /usr/local/bin/proton

# Create a proton-run helper script
cat > /usr/local/bin/proton-run << EOF
#!/bin/bash
# Helper script to run Windows executables with Proton
exec proton run "\$@"
EOF

chmod +x /usr/local/bin/proton-run
echo "✓ Proton helper scripts created"

# ===== Step 8: Setup on ARM64 if needed =====
if [ "$TARGETARCH" = "arm64" ]; then
    echo "Setting up Proton for ARM64..."
    
    # Check if box64 is installed
    if command -v box64 >/dev/null 2>&1; then
        echo "Creating ARM64-specific proton wrapper using box64"
        # Override the proton wrapper to use box64
        cat > /usr/local/bin/proton << EOF
#!/bin/bash
# ARM64 Proton wrapper script using box64
PROTON_BINARY="\${PROTON_PATH}/proton"

# Check if valid command
if [[ "\$1" == "run" ]]; then
    # Run a Windows executable through Proton with box64
    shift
    exec box64 "\$PROTON_BINARY" run "\$@"
elif [[ "\$1" == "waitforexitandrun" ]]; then
    # Wait for a process to finish and then run with box64
    shift
    exec box64 "\$PROTON_BINARY" waitforexitandrun "\$@"
else
    # Just pass all arguments to Proton with box64
    exec box64 "\$PROTON_BINARY" "\$@"
fi
EOF
        chmod +x /usr/local/bin/proton
        echo "✓ ARM64-specific proton wrapper created"
    else
        echo "✗ ERROR: box64 is not installed, Proton will not function correctly on ARM64."
        exit 1
    fi
fi

# ===== Step 9: Tests ==========================================
# FIXME for same reasons as boxes.sh, QEMU blocks box86 arm runs, x86 works. 
# echo "Running verification tests..."

# # Test Proton installation
# if command -v proton >/dev/null 2>&1; then
#     echo "✓ Proton command found"
    
#     # Run a basic test with the proton command
#     if proton --version > /tmp/proton_version.txt 2>&1; then
#         echo "✓ Proton version command successful"
#         cat /tmp/proton_version.txt
#     else
#         echo "! Warning: Proton version command returned non-zero exit code"
#         cat /tmp/proton_version.txt
#     fi
# else
#     echo "✗ ERROR: Proton installation failed - command not found"
#     exit 1
# fi

# echo "✓ All installation tests passed successfully!"

# ===== Step 10: Finalize installation =====
echo "Proton installation completed!"
echo "  Proton Version: ${PROTON_VERSION}"
echo "  Proton Path: ${PROTON_PATH}"
echo "  Proton Prefix: ${WINEPREFIX}"

# Re-source environment for current script
. /etc/environment

# Show final environment configuration
echo "Final environment configuration:"
cat /etc/environment

exit 0