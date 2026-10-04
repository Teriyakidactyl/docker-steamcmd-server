#!/bin/bash

if [ -z "${WINEPREFIX:-}" ]; then
    log "ERROR: WINEPREFIX is not set" "20_wine_prefix.sh"
    return 1
fi

PREFIX_TIMEOUT="${COMPAT_PREFIX_TIMEOUT:-300}"
READY_MARKER="$WINEPREFIX/.steamcmd-server-wine-ready"
BOOT_DLL_OVERRIDES="${WINE_BOOT_DLL_OVERRIDES-mscoree,mshtml=}"

if ! [[ "$PREFIX_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$PREFIX_TIMEOUT" -lt 1 ]; then
    log "ERROR: COMPAT_PREFIX_TIMEOUT must be a positive integer" "20_wine_prefix.sh"
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

stop_wineserver() {
    local action
    local -a cmd
    local -a arch_parts=()

    if [ -n "${ARCH_COMMAND_PREFIX:-}" ]; then
        read -r -a arch_parts <<< "$ARCH_COMMAND_PREFIX"
    fi

    for action in -k -w; do
        cmd=(
            timeout
            --signal=TERM
            --kill-after=5s
            15s
        )
        if [ "${#arch_parts[@]}" -gt 0 ]; then
            cmd+=("${arch_parts[@]}")
        fi
        cmd+=(wineserver "$action")
        "${cmd[@]}" >/dev/null 2>&1 || true
    done
}

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

    init_rc=0
    if [ -n "$BOOT_DLL_OVERRIDES" ]; then
        if WINEDLLOVERRIDES="$BOOT_DLL_OVERRIDES" run_logged "20_wine_prefix.sh" "${init_cmd[@]}"; then
            init_rc=0
        else
            init_rc=$?
        fi
    elif run_logged "20_wine_prefix.sh" "${init_cmd[@]}"; then
        init_rc=0
    else
        init_rc=$?
    fi

    # Wineboot can finish the useful prefix work while a detached Wine process
    # keeps its process tree or output descriptors alive. Always end that
    # initialization server before verification so the next command proves the
    # persisted prefix can start cleanly.
    stop_wineserver

    if [ "$init_rc" -ne 0 ]; then
        log "Wine prefix initialization command exited $init_rc; validating the resulting prefix before failing" "20_wine_prefix.sh"
    fi

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

    if run_logged "20_wine_prefix.sh" "${verify_cmd[@]}"; then
        verify_rc=0
    else
        verify_rc=$?
        stop_wineserver
        log "ERROR: Wine prefix operational verification failed with exit $verify_rc" "20_wine_prefix.sh"
        return 1
    fi
    stop_wineserver

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
