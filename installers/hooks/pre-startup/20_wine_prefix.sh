#!/bin/bash

# https://wiki.winehq.org/FAQ#Is_there_a_64_bit_Wine , https://wiki.winehq.org/FAQ#How_do_I_create_a_32_bit_wineprefix_on_a_64_bit_system?
# It requires the installation of 32 bit libraries in order to run 32 bit Windows applications

# Check first time wine run, this will force Wine config creation so that our server load won't fail on first run.
# TODO change to if $WINEPREFIX (path) is empty
if [ -n "$WINEPREFIX" ] && [ ! -d "$WINEPREFIX" ]; then
    # https://wiki.winehq.org/Wineboot
    log "Wine first run detected, wait 15 seconds for wine config creation."
    $APP_COMMAND_PREFIX wineboot -iuf | log_stdout
fi
