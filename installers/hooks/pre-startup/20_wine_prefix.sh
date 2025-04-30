#!/bin/bash

# https://wiki.winehq.org/FAQ#Is_there_a_64_bit_Wine , https://wiki.winehq.org/FAQ#How_do_I_create_a_32_bit_wineprefix_on_a_64_bit_system?
# It requires the installation of 32 bit libraries in order to run 32 bit Windows applications

# Check first time wine run, this will force Wine config creation so that our server load won't fail on first run.
if [ -z "$WINEPREFIX" ]; then
    # Error if WINEPREFIX is not set
    log "Error: WINEPREFIX variable is not set." "20_wine_prefix.sh"
elif [ ! -d "$WINEPREFIX" ]; then
    # Error if WINEPREFIX directory doesn't exist
    log "Error: WINEPREFIX '$WINEPREFIX' directory does not exist." "20_wine_prefix.sh"
elif [ ! "$(ls -A "$WINEPREFIX")" ]; then
    # If WINEPREFIX directory exists but is empty, run wineboot
    log "WINEPREFIX '$WINEPREFIX' exists but is empty, initializing wine." "20_wine_prefix.sh"
    $APP_COMMAND_PREFIX wineboot -iuf | log_stdout "20_wine_prefix.sh"
else
    # If WINEPREFIX directory exists and has files
    log "Wine prefix exists at '$WINEPREFIX'." "20_wine_prefix.sh"
fi