#!/bin/bash

# TODO verify required ENV are not null
# STEAM_SERVER_APPID="" \
# STEAM_PLATFORM_TYPE="linux" \
# APP_NAME="valheim" \
# APP_EXE="valheim_server.x86_64" \
# APP_COMMAND

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