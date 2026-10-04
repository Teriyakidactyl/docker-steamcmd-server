#!/bin/bash

if [ -z "${WINEPREFIX:-}" ]; then
    log "ERROR: WINEPREFIX is not set" "20_wine_prefix.sh"
    return 1
fi

PREFIX_TIMEOUT="${COMPAT_PREFIX_TIMEOUT:-300}"
READY_MARKER="$WINEPREFIX/.steamcmd-server-wine-ready"

if ! [[ "$PREFIX_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$PREFIX_TIMEOUT" -lt 1 ]; then
    log "ERROR: COMPAT_PREFIX_TIMEOUT must be a positive integer" "20_wine_prefix.sh"
    return 1
fi

mkdir -p "$WINEPREFIX"

if [ ! -f "$READY_MARKER" ]; then
    if [ -n "$(ls -A "$WINEPREFIX" 2>/dev/null)" ]; then
        log "Wine prefix is present without a readiness marker; retrying initialization at $WINEPREFIX" "20_wine_prefix.sh"
    else
        log "Initializing Wine prefix at $WINEPREFIX" "20_wine_prefix.sh"
    fi

    declare -a init_cmd=(
        timeout
        --signal=TERM
        --kill-after=10s
        "${PREFIX_TIMEOUT}s"
        xvfb-run
        --auto-servernum
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp"
    )
    if [ -n "${ARCH_COMMAND_PREFIX:-}" ]; then
        read -r -a arch_parts <<< "$ARCH_COMMAND_PREFIX"
        init_cmd+=("${arch_parts[@]}")
    fi
    init_cmd+=(wineboot -iuf)
    "${init_cmd[@]}" | log_stdout "20_wine_prefix.sh"

    declare -a verify_cmd=(
        timeout
        --signal=TERM
        --kill-after=10s
        "${PREFIX_TIMEOUT}s"
        xvfb-run
        --auto-servernum
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp"
    )
    if [ -n "${ARCH_COMMAND_PREFIX:-}" ]; then
        read -r -a arch_parts <<< "$ARCH_COMMAND_PREFIX"
        verify_cmd+=("${arch_parts[@]}")
    fi
    read -r -a compat_parts <<< "${COMPAT_COMMAND:-wine}"
    verify_cmd+=("${compat_parts[@]}" cmd /c ver)
    "${verify_cmd[@]}" | log_stdout "20_wine_prefix.sh"

    if [ ! -s "$WINEPREFIX/system.reg" ]; then
        log "ERROR: Wine prefix initialization did not create system.reg" "20_wine_prefix.sh"
        return 1
    fi

    if [ "${WINEARCH:-}" = "wow64" ] && [ ! -f "$WINEPREFIX/drive_c/windows/syswow64/regedit.exe" ]; then
        log "ERROR: WoW64 prefix is missing C:\\windows\\syswow64\\regedit.exe" "20_wine_prefix.sh"
        return 1
    fi

    touch "$READY_MARKER"
    log "Wine prefix is ready at $WINEPREFIX" "20_wine_prefix.sh"
else
    log "Wine prefix is ready at $WINEPREFIX" "20_wine_prefix.sh"
fi
