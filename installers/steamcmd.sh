#!/usr/bin/env bash

#!/bin/bash
# SteamCMD installation script for Docker SteamCMD Server
# Handles installation of Valve's Steam Console Client
#
# This script:
# - Downloads and extracts SteamCMD
# - Configures environment variables for SteamCMD
# - Adds convenience aliases

set -eo pipefail

# Display header
echo "------------------------------------------------------- SteamCMD Installation -----------------------------------------------------------------------"

# Verify required parameters are provided
if [ -z "$STEAMCMD_PATH" ]; then
    echo "✗ ERROR: STEAMCMD_PATH is required but not set"
    exit 1
fi

if [ -z "$CONTAINER_USER" ]; then
    echo "✗ ERROR: CONTAINER_USER is required but not set"
    exit 1
fi

# Log configuration
echo "SteamCMD Configuration:"
echo "  SteamCMD Path: ${STEAMCMD_PATH}"
echo "  Container User: ${CONTAINER_USER}"

# ===== Step 1: Setup environment variables =====
echo "Setting up environment variables..."

# Add SteamCMD configuration to environment file
cat << 'EOT' >> /etc/environment

# SteamCMD configuration
export STEAMCMD_EXEC="${STEAMCMD_PATH}/steamcmd.sh"
EOT

# ===== Step 2: Add user aliases =====
echo "Adding user aliases..."

# Add steamcmd alias to bash profile
# FIXME aliases don't persist to subshells, not really used other than for manual testing
cat << 'EOT' >> /home/${CONTAINER_USER}/.bashrc

# SteamCMD aliases and shortcuts
alias steamcmd="$STEAMCMD_EXEC"
EOT

# ===== Step 3: Create directories and download SteamCMD =====
echo "Creating directories and downloading SteamCMD..."

mkdir -p ${STEAMCMD_PATH}
echo "Downloading SteamCMD from: https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ${STEAMCMD_PATH}

# Create Steam SDK directories if they don't exist
mkdir -p $STEAMCMD_PROFILE/sdk32 $STEAMCMD_PROFILE/sdk64

# Create symbolic links for Steam libraries, better than using 'export LD_LIBRARY_PATH=$STEAMCMD_PATH/linux32
ln -sf ${STEAMCMD_PATH}/linux32/steamclient.so $STEAMCMD_PROFILE/sdk32/steamclient.so
ln -sf ${STEAMCMD_PATH}/linux64/steamclient.so $STEAMCMD_PROFILE/sdk64/steamclient.so

chmod +x ${STEAMCMD_PATH}/steamcmd.sh
chown -R ${CONTAINER_USER}:${CONTAINER_USER} ${STEAMCMD_PATH}

# ===== Step 5: Test SteamCMD functionality ==========================================
echo "Testing SteamCMD functionality..."

# Create a known note about the first-run error
# NOTE ILocalize::AddFile() failed to load file "public/steambootstrapper_english.txt"
# ^ is an error related to first-run where public doesn't yet exist.

# Re-source environment for current script
. /etc/environment

# FIXME for same reasons as boxes.sh, QEMU blocks box86 arm runs, x86 works. 
# Run SteamCMD with anonymous login and quit as $CONTAINER_USER
# su - ${CONTAINER_USER} -c "${STEAMCMD_PATH}/steamcmd.sh +login anonymous +quit" | tee /tmp/steamcmd_output.log

# # Check for success indicators in the output
# if grep -q 'Update complete\|Success! App .* already up to date\|Logged in OK' /tmp/steamcmd_output.log; then
#     echo "✓ SteamCMD test passed - login successful"
# else
#     echo "✗ SteamCMD test failed"
#     echo "Output from SteamCMD:"
#     cat /tmp/steamcmd_output.log
#     exit 1
# fi

# ===== Step 6: Finalize installation =====
echo "SteamCMD installation completed!"

# Show final environment configuration
echo "Final environment configuration:"
cat /etc/environment

exit 0