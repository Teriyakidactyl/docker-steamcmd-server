#!/bin/bash

# Proton WINEPREFIX initialization script
# Ensures that the Proton prefix is properly initialized before server start
# This is equivalent to Wine's prefix initialization but adapted for Proton

# Check if WINEPREFIX is set and prepare it if needed
if [ -z "$WINEPREFIX" ]; then
    # Error if WINEPREFIX is not set
    log "Error: WINEPREFIX variable is not set." "20_proton_prefix.sh"
elif [ ! -d "$WINEPREFIX" ]; then
    # Error if WINEPREFIX directory doesn't exist
    log "Error: WINEPREFIX '$WINEPREFIX' directory does not exist." "20_proton_prefix.sh"
elif [ ! "$(ls -A "$WINEPREFIX")" ]; then
    # If WINEPREFIX directory exists but is empty, initialize it using Proton
    log "WINEPREFIX '$WINEPREFIX' exists but is empty, initializing Proton prefix." "20_proton_prefix.sh"
    
    # Check if we have direct proton reference or need to use APP_COMMAND_PREFIX
    if command -v proton >/dev/null 2>&1; then
        # Run proton with a minimal command to initialize the prefix
        proton run wineboot -iuf | log_stdout "20_proton_prefix.sh"
    else
        # Use the APP_COMMAND_PREFIX which should contain "proton run"
        $APP_COMMAND_PREFIX wineboot -iuf | log_stdout "20_proton_prefix.sh"
    fi
else
    # If WINEPREFIX directory exists and has files
    log "Proton prefix exists at '$WINEPREFIX'." "20_proton_prefix.sh"
fi

# Optionally check for Steam compatibility data path
if [ -n "$STEAM_COMPAT_DATA_PATH" ] && [ "$STEAM_COMPAT_DATA_PATH" != "$WINEPREFIX" ]; then
    log "Note: STEAM_COMPAT_DATA_PATH is set to '$STEAM_COMPAT_DATA_PATH', which differs from WINEPREFIX." "20_proton_prefix.sh"
    
    if [ ! -d "$STEAM_COMPAT_DATA_PATH" ] || [ ! "$(ls -A "$STEAM_COMPAT_DATA_PATH")" ]; then
        log "Creating symlink from WINEPREFIX to STEAM_COMPAT_DATA_PATH for compatibility." "20_proton_prefix.sh"
        mkdir -p "$STEAM_COMPAT_DATA_PATH"
        ln -sf "$WINEPREFIX/"* "$STEAM_COMPAT_DATA_PATH/"
    fi
fi

