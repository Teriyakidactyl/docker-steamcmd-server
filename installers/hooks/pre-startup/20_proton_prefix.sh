#!/bin/bash

if [ -z "${WINEPREFIX:-}" ]; then
    log "ERROR: WINEPREFIX is not set" "20_proton_prefix.sh"
    return 1
fi

mkdir -p "$WINEPREFIX"

if [ -z "$(ls -A "$WINEPREFIX" 2>/dev/null)" ]; then
    log "Initializing Proton prefix at $WINEPREFIX" "20_proton_prefix.sh"
    xvfb-run \
        --auto-servernum \
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp" \
        proton runinprefix wineboot -iuf | log_stdout "20_proton_prefix.sh"
else
    log "Proton prefix exists at $WINEPREFIX" "20_proton_prefix.sh"
fi
