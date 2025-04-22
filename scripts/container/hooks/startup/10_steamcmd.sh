#!/bin/bash

# Verify each required environment variable
REQUIRED_VARS=("STEAM_SERVER_APPID" "STEAM_PLATFORM_TYPE" "APP_NAME" "APP_FILES")
log "Verifying required environment variables..."
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    log "Error: Required environment variable '$var' is not set or is empty."
    exit 1
  fi
done
log "All required environment variables are set."

# Initialize SteamCMD if needed
if [ ! -d "$STEAMCMD_PROFILE" ]; then
    log "$STEAMCMD_PROFILE directory not complete, presuming first run."
    $STEAMCMD_EXEC +login anonymous +quit | log_stdout "steamcmd"
fi

# Create appinfo directory if it doesn't exist
APPINFO_DIR="$PWD/appinfo"
mkdir -p "$APPINFO_DIR"

# Set file paths for storing app info
APPID="$STEAM_SERVER_APPID"
APPINFO_FILE="$APPINFO_DIR/$APPID"
APPINFO_FILE_NEW="$APPINFO_DIR/${APPID}-new"

log "Checking for needed updates for game id $APPID"

# Get current app info from API
if ! curl "https://api.steamcmd.net/v1/info/$APPID" --silent --output "$APPINFO_FILE_NEW"; then
    log "Error getting app info for game"
    exit 1
fi

# Check if an update is needed by comparing the new info with the stored info
NEEDS_UPDATE=1
if [ -f "$APPINFO_FILE" ]; then
    if cmp -s "$APPINFO_FILE" "$APPINFO_FILE_NEW"; then
        NEEDS_UPDATE=0
    fi
fi

if [ $NEEDS_UPDATE -ne 0 ]; then
    log "Update required, installing to $APP_FILES"
    
    # Run SteamCMD to update the app
    $STEAMCMD_EXEC \
    +@sSteamCmdForcePlatformType "$STEAM_PLATFORM_TYPE" \
    +force_install_dir "$APP_FILES" \
    +login anonymous \
    +app_update "$APPID" \
    validate \
    +quit | log_stdout "steamcmd"
    
    if [ $? -ne 0 ]; then
        log "Error updating app via steamcmd"
        exit 1
    fi
    
    # Save the new app info file for future comparisons
    mv "$APPINFO_FILE_NEW" "$APPINFO_FILE"
    
    log "Version was out-of-date, update applied"
    exit 1
else
    log "Version up-to-date, no update needed"
    rm "$APPINFO_FILE_NEW"
    exit 0
fi