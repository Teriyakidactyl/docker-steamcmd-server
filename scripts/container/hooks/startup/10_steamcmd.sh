#!/bin/bash

# Verify each required environment variable
REQUIRED_VARS=("STEAM_SERVER_APPID" "STEAM_PLATFORM_TYPE" "APP_NAME" "APP_FILES")
log "Verifying required environment variables..."
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    log "Error: Required environment variable '$var' is not set or is empty." "10_steamcmd.sh"
    exit 1
  fi
done
log "All required environment variables are set."

# Initialize SteamCMD if needed
if [ ! -d "$STEAMCMD_PROFILE" ]; then
    log "$STEAMCMD_PROFILE directory not complete, presuming first run." "10_steamcmd.sh"
    $STEAMCMD_EXEC +login anonymous +quit | log_stdout "10_steamcmd.sh"
fi

# Create appinfo directory if it doesn't exist
APPINFO_DIR="$APP_FILES/appinfo"
mkdir -p "$APPINFO_DIR"

# Set file paths for storing app info
APPINFO_FILE="$APPINFO_DIR/$STEAM_SERVER_APPID"
APPINFO_FILE_NEW="$APPINFO_DIR/${STEAM_SERVER_APPID}-new"

log "Checking for needed updates for game id $STEAM_SERVER_APPID" "10_steamcmd.sh"

# Get current app info from API
if ! curl "https://api.steamcmd.net/v1/info/$STEAM_SERVER_APPID" --silent --output "$APPINFO_FILE_NEW"; then
    log "Error getting app info for game" "10_steamcmd.sh"
fi

# Check if an update is needed by comparing the new info with the stored info
NEEDS_UPDATE=1
if [ -f "$APPINFO_FILE" ]; then
    if cmp -s "$APPINFO_FILE" "$APPINFO_FILE_NEW"; then
        NEEDS_UPDATE=0
    fi
fi

if [ $NEEDS_UPDATE -ne 0 ]; then
    log "Update required, installing to $APP_FILES" "10_steamcmd.sh"
    UPDATE_OUTPUT_FILE=$(mktemp)
   
    # Run SteamCMD to update the app
    $STEAMCMD_EXEC \
    +@sSteamCmdForcePlatformType "$STEAM_PLATFORM_TYPE" \
    +force_install_dir "$APP_FILES" \
    +login anonymous \
    +app_update "$STEAM_SERVER_APPID" \
    validate \
    +quit | tee "$UPDATE_OUTPUT_FILE" | log_stdout "10_steamcmd.sh"
   
    # Check for success message in the output
    if grep -q "Success! App '$STEAM_SERVER_APPID' fully installed" "$UPDATE_OUTPUT_FILE"; then
        # Save the new app info file since update succeeded
        mv "$APPINFO_FILE_NEW" "$APPINFO_FILE"
        log "Version was out-of-date, update applied successfully" "10_steamcmd.sh"
    else
        # If success message not found, assume failure
        log "Error updating app via steamcmd (success message not found)" "10_steamcmd.sh"
        rm "$APPINFO_FILE_NEW"  # Remove the new appinfo file since update failed
    fi
    
    # Clean up temp file
    rm "$UPDATE_OUTPUT_FILE"
else
    log "Version up-to-date, no update needed" "10_steamcmd.sh"
    rm "$APPINFO_FILE_NEW"
fi
