#!/bin/bash

if [ -z "${WINEPREFIX:-}" ]; then
    log "ERROR: WINEPREFIX is not set" "20_wine_prefix.sh"
    return 1
fi

mkdir -p "$WINEPREFIX"

if [ -z "$(ls -A "$WINEPREFIX" 2>/dev/null)" ]; then
    log "Initializing Wine prefix at $WINEPREFIX" "20_wine_prefix.sh"
    declare -a cmd=(
        xvfb-run
        --auto-servernum
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp"
    )
    if [ -n "${ARCH_COMMAND_PREFIX:-}" ]; then
        read -r -a arch_parts <<< "$ARCH_COMMAND_PREFIX"
        cmd+=("${arch_parts[@]}")
    fi
    cmd+=(wineboot -iuf)
    "${cmd[@]}" | log_stdout "20_wine_prefix.sh"
else
    log "Wine prefix exists at $WINEPREFIX" "20_wine_prefix.sh"
fi
