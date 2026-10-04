#!/bin/bash

if [ -z "${WINEPREFIX:-}" ]; then
    log "ERROR: WINEPREFIX is not set" "20_proton_prefix.sh"
    return 1
fi

PREFIX_TIMEOUT="${COMPAT_PREFIX_TIMEOUT:-300}"
# Proton has the same interrupted-prefix hazard as Wine: wineboot can leave
# non-empty compatibility data without producing a usable prefix. A completion
# marker is therefore written only after an independent Windows command and
# registry assertion succeed.
READY_MARKER="$WINEPREFIX/.steamcmd-server-proton-ready"
PROTON_PREFIX="$WINEPREFIX/pfx"

if ! [[ "$PREFIX_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$PREFIX_TIMEOUT" -lt 1 ]; then
    log "ERROR: COMPAT_PREFIX_TIMEOUT must be a positive integer" "20_proton_prefix.sh"
    return 1
fi

run_logged() {
    local source_name="$1"
    shift
    local output_file
    local rc=0

    output_file="$(mktemp)"
    if "$@" >"$output_file" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    if [ -s "$output_file" ]; then
        log_stdout "$source_name" < "$output_file"
    fi
    rm -f "$output_file"
    return "$rc"
}

stop_proton_wineserver() {
    # Proton/Wine may leave helper processes or inherited output descriptors
    # alive after wineboot. Kill and then wait before verification so cmd /c ver
    # proves that the persisted prefix can start cleanly in a fresh invocation.
    timeout \
        --signal=TERM \
        --kill-after=5s \
        15s \
        proton runinprefix wineserver -k \
        >/dev/null 2>&1 || true
    timeout \
        --signal=TERM \
        --kill-after=5s \
        15s \
        proton runinprefix wineserver -w \
        >/dev/null 2>&1 || true
}

mkdir -p "$WINEPREFIX"

if [ ! -f "$READY_MARKER" ]; then
    if [ -n "$(ls -A "$WINEPREFIX" 2>/dev/null)" ]; then
        log "Proton compatibility data is present without a readiness marker; retrying initialization at $WINEPREFIX" "20_proton_prefix.sh"
    else
        log "Initializing Proton prefix at $WINEPREFIX" "20_proton_prefix.sh"
    fi

    declare -a init_cmd=(
        timeout
        --signal=TERM
        --kill-after=10s
        "${PREFIX_TIMEOUT}s"
        xvfb-run
        --auto-servernum
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp"
        proton
        runinprefix
        wineboot
        -iuf
    )

    # As with Wine, initialization output/exit can be noisy even when the
    # resulting prefix is usable. Treat the later operational command as the
    # authoritative capability check instead of accepting/rejecting on wineboot
    # alone.
    init_rc=0
    if run_logged "20_proton_prefix.sh" "${init_cmd[@]}"; then
        init_rc=0
    else
        init_rc=$?
    fi
    stop_proton_wineserver

    if [ "$init_rc" -ne 0 ]; then
        log "Proton prefix initialization command exited $init_rc; validating the resulting prefix before failing" "20_proton_prefix.sh"
    fi

    declare -a verify_cmd=(
        timeout
        --signal=TERM
        --kill-after=10s
        "${PREFIX_TIMEOUT}s"
        xvfb-run
        --auto-servernum
        "--server-args=-screen 0 640x480x24:32 -nolisten tcp"
        proton
        runinprefix
        cmd
        /c
        ver
    )

    if run_logged "20_proton_prefix.sh" "${verify_cmd[@]}"; then
        verify_rc=0
    else
        verify_rc=$?
        stop_proton_wineserver
        log "ERROR: Proton prefix operational verification failed with exit $verify_rc" "20_proton_prefix.sh"
        return 1
    fi
    stop_proton_wineserver

    if [ ! -s "$PROTON_PREFIX/system.reg" ]; then
        log "ERROR: Proton prefix initialization did not create pfx/system.reg" "20_proton_prefix.sh"
        return 1
    fi

    touch "$READY_MARKER"
    log "Proton prefix is ready at $PROTON_PREFIX" "20_proton_prefix.sh"
else
    log "Proton prefix is ready at $PROTON_PREFIX" "20_proton_prefix.sh"
fi
