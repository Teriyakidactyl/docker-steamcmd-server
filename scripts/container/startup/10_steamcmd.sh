#!/bin/bash

# Verify each required environment variable
REQUIRED_VARS=("STEAM_SERVER_APPID" "STEAM_PLATFORM_TYPE" "APP_NAME" "APP_EXE")
echo "Verifying required environment variables..."
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: Required environment variable '$var' is not set or is empty."
    exit 1
  fi
done
echo "All required environment variables are set."

# Initialize SteamCMD if needed
if [ ! -d "$STEAMCMD_PROFILE" ]; then
    log "$STEAMCMD_PATH directory not complete, presuming first run." "update"
    steamcmd +login anonymous +quit | log_stdout "steamcmd"
fi

# Update server 
# Refference: https://developer.valvesoftware.com/wiki/SteamCMD
# TODO Check server version before updating
log "SteamCMD beginning download of $APP_NAME"

steamcmd \
+@sSteamCmdForcePlatformType $STEAM_PLATFORM_TYPE \
+force_install_dir $APP_FILES \
+login anonymous \
+app_update $STEAM_SERVER_APPID \
validate \
+quit | log_stdout "steamcmd"

# TODO Implement APP_FILES exists check