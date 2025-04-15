docker run --rm -it --platform=linux/arm64 --name steamcmd-test debian:bookworm-slim bash

#!/bin/bash

# Update and install necessary packages
apt-get update
apt-get install -y curl tar ca-certificates tzdata dpkg

# Install dependencies for Box86
dpkg --add-architecture armhf
apt-get update
apt-get install -y libc6:armhf

# Set Box86 environment variables
export DEBUGGER="box86"
export BOX86_LOG=1
export BOX86_TRACE_FILE="/var/log/box86.log"

# Create directories
mkdir -p /opt/steamcmd /var/log

# Install Box86 from the specified URL
BOX86_DEB_URL="https://github.com/ryanfortner/box86-debs/raw/refs/heads/master/debian/box86-generic-arm_0.3.9+20250223.c13b3cc-1_armhf.deb"
curl -L "$BOX86_DEB_URL" -o /tmp/box86.deb
dpkg -i /tmp/box86.deb || apt-get -f install -y
rm -f /tmp/box86.deb

# Ensure Box86 executable has proper permissions
chmod +x /usr/local/bin/box86

# Download and install SteamCMD
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C /opt/steamcmd

# Test SteamCMD with Box86
opt/steamcmd/steamcmd.sh +login anonymous +quit

opt/steamcmd/steamcmd.sh \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "$APP_FILES\232330" \
    +login anonymous \
    +app_update 232330 validate \
    +quit

opt/steamcmd/steamcmd.sh \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "$APP_FILES\740" \
    +login anonymous \
    +app_update 740 validate \
    +quit