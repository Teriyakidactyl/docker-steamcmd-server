#!/bin/bash

if [ -z "${WINEPREFIX:-}" ]; then
    log "ERROR: WINEPREFIX is not set" "20_proton_prefix.sh"
    return 1
fi

PREFIX_TIMEOUT="${COMPAT_PREFIX_TIMEOUT:-300}"
READY_MARKER="$WINEPREFIX/.steamcmd-server-proton-ready"
PROTON_PREFIX="$WINEPREFIX/pfx"

if ! [[ "$PREFIX_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$PREFIX_TIMEOUT" -lt 1 ]; then
    log "ERROR: COMPAT_PREFIX_TIMEOUT must be a positive integer" "20_proton_prefix.sh"
    return 1
fi

mkdir -p "$WINEPREFIX"

if [ ! -f "$READY_MARKER" ]; then
    if [ -n "$(ls -A "$WINEPREFIX" 2>/dev/null)" ]; then
        log "Proton compatibility data is present without a readiness marker; retrying initialization at $WINEPREFIX" "20_proton_prefix.sh"
    else
        log "Initializing Proton prefix at $WINEPREFIX" "20_proton_prefix.sh"
    fi

    timeout \
        --signal=TERM \
        --kill-after=10s \
        "${PREFIX_TIMEOUT}s" \
        xvfb-run \
        --auto-servernum \
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp" \
        proton runinprefix wineboot -iuf \
        | log_stdout "20_proton_prefix.sh"

    timeout \
        --signal=TERM \
        --kill-after=10s \
        "${PREFIX_TIMEOUT}s" \
        xvfb-run \
        --auto-servernum \
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp" \
        proton runinprefix cmd /c ver \
        | log_stdout "20_proton_prefix.sh"

    if [ ! -s "$PROTON_PREFIX/system.reg" ]; then
        log "ERROR: Proton prefix initialization did not create pfx/system.reg" "20_proton_prefix.sh"
        return 1
    fi

    touch "$READY_MARKER"
    log "Proton prefix is ready at $PROTON_PREFIX" "20_proton_prefix.sh"
else
    log "Proton prefix is ready at $PROTON_PREFIX" "20_proton_prefix.sh"
fi
