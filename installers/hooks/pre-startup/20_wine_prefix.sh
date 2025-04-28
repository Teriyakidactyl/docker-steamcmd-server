#!/bin/bash

# https://wiki.winehq.org/FAQ#Is_there_a_64_bit_Wine , https://wiki.winehq.org/FAQ#How_do_I_create_a_32_bit_wineprefix_on_a_64_bit_system?
# It requires the installation of 32 bit libraries in order to run 32 bit Windows applications

# Check first time wine run, this will force Wine config creation so that our server load won't fail on first run.

if [ -z "$WINEPREFIX" ]; then
    # https://wiki.winehq.org/Wineboot
    log "Wine prefix is empty, running wineboot to initialize." "20_wine_prefix.sh"
    $APP_COMMAND_PREFIX wineboot -iuf | log_stdout "20_wine_prefix.sh"
elif [ ! -d "$WINEPREFIX" ]; then
    log "WINEPREFIX '$WINEPREFIX' does not exist, attempting to initialize." "20_wine_prefix.sh"
    $APP_COMMAND_PREFIX wineboot -iuf | log_stdout "20_wine_prefix.sh"
fi
