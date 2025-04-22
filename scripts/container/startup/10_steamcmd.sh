#!/bin/bash

# Initialize SteamCMD if needed
if [ ! -d "$STEAMCMD_PROFILE" ]; then
    log "$STEAMCMD_PATH directory not complete, presuming first run." "update"
    steamcmd +login anonymous +quit | log_stdout "steamcmd"
fi

# Update server 
# Refference: https://developer.valvesoftware.com/wiki/SteamCMD
# TODO Check server version before updating
log "SteamCMD begining download of $APP_NAME"

steamcmd \
+@sSteamCmdForcePlatformType linux \
+force_install_dir $APP_FILES \
+login anonymous \
+app_update $STEAM_SERVER_APPID \
validate \
+quit | log_stdout "steamcmd"

# TODO Implement APP_FILES exists check