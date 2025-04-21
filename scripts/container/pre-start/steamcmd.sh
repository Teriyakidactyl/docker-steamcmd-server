#!/bin/bash

# Initialize SteamCMD if needed
if [ ! -d "$STEAMCMD_PROFILE" ]; then
    log "$STEAMCMD_PATH directory not complete, presuming first run." "update"
    steamcmd +login anonymous +quit | log_stdout "steamcmd"
fi