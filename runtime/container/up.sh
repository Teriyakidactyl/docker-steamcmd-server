#!/bin/bash

set -Eeuo pipefail

if [ -f /etc/environment ]; then
    # shellcheck disable=SC1091
    source /etc/environment
fi
# shellcheck disable=SC1091
source "$SCRIPTS/container/logging.sh"

CONTAINER_START_TIME=${CONTAINER_START_TIME:-$(date -u +%s)}
APP_PID=""
APP_PGID=""
SHUTDOWN_REQUESTED=0
APPLICATION_GROUP_SNAPSHOT_COUNT=0
declare -a APP_COMMAND_ARRAY=()

run_hooks() {
    local hook_type="$1"
    local failure_mode="${2:-fatal}"
    local hook_dir="$HOOK_DIRECTORIES/$hook_type"

    if [ ! -d "$hook_dir" ]; then
        return 0
    fi

    local hook
    while IFS= read -r hook; do
        [ -n "$hook" ] || continue
        log "Sourcing $(basename "$hook")" "hooks"
        if [ "$failure_mode" = "fatal" ]; then
            # Keep fatal hooks out of a conditional command context so Bash
            # errexit semantics inside the sourced hook remain effective.
            source "$hook"
        elif ! source "$hook"; then
            log "ERROR sourcing $(basename "$hook")" "hooks"
        fi
    done < <(find "$hook_dir" -type f -executable -print | sort)
}

append_words() {
    local value="$1"
    local -a parts=()
    [ -n "$value" ] || return 0
    read -r -a parts <<< "$value"
    APP_COMMAND_ARRAY+=("${parts[@]}")
}

build_command() {
    APP_COMMAND_ARRAY=()

    if [ -n "${APP_COMMAND:-}" ]; then
        log "Using legacy APP_COMMAND override" "up.sh"
        APP_COMMAND_ARRAY=(/bin/bash -lc "$APP_COMMAND")
        return 0
    fi

    local executable="${APP_EXECUTABLE:-}"
    if [ -z "$executable" ]; then
        if [ -z "${APP_EXE:-}" ]; then
            log "ERROR: APP_EXE or APP_EXECUTABLE must be set" "up.sh"
            return 1
        fi
        executable="$APP_FILES/$APP_EXE"
    fi

    if [ "${APP_USE_XVFB:-false}" = "true" ]; then
        APP_COMMAND_ARRAY+=(
            xvfb-run
            --auto-servernum
            "--server-args=-screen 0 640x480x24:32 -nolisten tcp"
        )
    fi

    append_words "${ARCH_COMMAND_PREFIX:-}"
    append_words "${COMPAT_COMMAND:-}"
    # Backward compatibility for derivative images that still set APP_COMMAND_PREFIX.
    append_words "${APP_COMMAND_PREFIX:-}"
    APP_COMMAND_ARRAY+=("$executable")

    if [ -n "${APP_ARGS_FILE:-}" ]; then
        if [ ! -f "$APP_ARGS_FILE" ]; then
            log "ERROR: APP_ARGS_FILE does not exist: $APP_ARGS_FILE" "up.sh"
            return 1
        fi
        local line expanded
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            expanded="$(printf '%s' "$line" | envsubst)"
            APP_COMMAND_ARRAY+=("$expanded")
        done < "$APP_ARGS_FILE"
    elif [ -n "${APP_ARGS:-}" ]; then
        log "APP_ARGS string mode is deprecated; prefer APP_ARGS_FILE for safe argument boundaries" "up.sh"
        local -a legacy_args=()
        # APP_ARGS is maintained for compatibility with existing child images.
        # New images should use APP_ARGS_FILE, which does not evaluate shell syntax.
        # shellcheck disable=SC2206
        eval "legacy_args=( $APP_ARGS )"
        APP_COMMAND_ARRAY+=("${legacy_args[@]}")
    fi
}

log_command() {
    local rendered=""
    local arg
    for arg in "${APP_COMMAND_ARRAY[@]}"; do
        printf -v rendered '%s %q' "$rendered" "$arg"
    done
    log "Launching application: $APP_NAME" "up.sh"
    log "${rendered# }" "up.sh"
}

initialize_cron() {
    LAST_HOURLY_RUN=$(date +%H)
    LAST_DAILY_RUN=$(date +%d)
    LAST_WEEKLY_RUN=$(date +%U)
    LAST_MONTHLY_RUN=$(date +%m)
}

uptime_text() {
    local now uptime_seconds days hours minutes
    now=$(date -u +%s)
    uptime_seconds=$(( now - CONTAINER_START_TIME ))
    days=$(( uptime_seconds / 86400 ))
    hours=$(( (uptime_seconds % 86400) / 3600 ))
    minutes=$(( (uptime_seconds % 3600) / 60 ))
    printf 'Container Uptime: %dd %dh %dm' "$days" "$hours" "$minutes"
}

run_cron_hooks() {
    local current_minute current_hour current_day current_week current_month
    current_minute=$(date '+%M')
    current_minute=${current_minute#0}
    current_minute=${current_minute:-0}
    current_hour=$(date '+%H')
    current_day=$(date '+%d')
    current_week=$(date '+%U')
    current_month=$(date '+%m')

    if [ "$current_hour" != "$LAST_HOURLY_RUN" ]; then
        run_hooks "hourly" nonfatal
        LAST_HOURLY_RUN=$current_hour
    fi

    local daily_hour=${CRON_DAILY_HOUR:-03}
    if [ "$current_hour" = "$daily_hour" ] && [ "$current_day" != "$LAST_DAILY_RUN" ]; then
        run_hooks "daily" nonfatal
        LAST_DAILY_RUN=$current_day
    fi

    local weekly_day=${CRON_WEEKLY_DAY:-0}
    local weekly_hour=${CRON_WEEKLY_HOUR:-04}
    if [ "$(date '+%w')" = "$weekly_day" ] && [ "$current_hour" = "$weekly_hour" ] && [ "$current_week" != "$LAST_WEEKLY_RUN" ]; then
        run_hooks "weekly" nonfatal
        LAST_WEEKLY_RUN=$current_week
    fi

    local monthly_day=${CRON_MONTHLY_DAY:-01}
    local monthly_hour=${CRON_MONTHLY_HOUR:-05}
    if [ "$current_day" = "$monthly_day" ] && [ "$current_hour" = "$monthly_hour" ] && [ "$current_month" != "$LAST_MONTHLY_RUN" ]; then
        run_hooks "monthly" nonfatal
        LAST_MONTHLY_RUN=$current_month
    fi

    if [ "${LOG_UPTIME:-true}" = "true" ] && (( current_minute % 10 == 0 )); then
        log "$(uptime_text)" "cron"
    fi
}

stop_tailers() {
    if [ -n "${TAIL_PGID:-}" ]; then
        kill -TERM -- "-$TAIL_PGID" 2>/dev/null || true
    fi
}

application_group_alive() {
    [ -n "${APP_PGID:-}" ] || return 1
    kill -0 -- "-$APP_PGID" 2>/dev/null
}

application_group_members() {
    [ -n "${APP_PGID:-}" ] || return 0

    local proc pid stat rest state ppid pgrp comm
    for proc in /proc/[0-9]*; do
        [ -r "$proc/stat" ] || continue
        if ! IFS= read -r stat < "$proc/stat"; then
            continue
        fi

        # /proc/<pid>/stat wraps the process name in parentheses. Strip through
        # the final ") " delimiter so names containing spaces remain intact.
        rest=${stat##*) }
        [ "$rest" != "$stat" ] || continue

        state=${rest%% *}
        rest=${rest#* }
        ppid=${rest%% *}
        rest=${rest#* }
        pgrp=${rest%% *}
        [ "$pgrp" = "$APP_PGID" ] || continue

        pid=${proc#/proc/}
        comm=${stat#*(}
        comm=${comm%)*}
        comm=${comm//
handle_signal() {
    local signal="$1"
    SHUTDOWN_REQUESTED=1
    log "Received $signal; beginning shutdown" "up.sh"
    stop_application
    exit 0
}

on_exit() {
    local rc=$?
    trap - EXIT
    stop_tailers
    if [ -n "${APP_PID_FILE:-}" ]; then
        rm -f "$APP_PID_FILE"
    fi
    exit "$rc"
}

main() {
    initialize_cron
    log_clean
    run_hooks "pre-startup"
    run_hooks "startup"
    build_command
    log_command

    local log_name="${APP_LOG_NAME:-${APP_EXE##*/}}"
    log_name="${log_name//\//_}"
    [ -n "$log_name" ] || log_name="application"

    mkdir -p "$(dirname "$APP_PID_FILE")" "$LOGS"
    rm -f "$APP_PID_FILE"

    # Bash starts asynchronous commands with SIGINT and SIGQUIT ignored when
    # job control is disabled. Reset those inherited dispositions before exec
    # so child images can use APP_STOP_SIGNAL=INT or QUIT reliably.
    setsid env --default-signal=INT --default-signal=QUIT -- "${APP_COMMAND_ARRAY[@]}" >> "$LOGS/$log_name.log" 2>&1 &
    APP_PID=$!
    APP_PGID=$APP_PID
    printf '%s\n' "$APP_PID" > "$APP_PID_FILE"

    sleep 1
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        local early_rc=0
        wait "$APP_PID" || early_rc=$?
        log "Application exited during startup verification with status $early_rc" "up.sh"
        return "$early_rc"
    fi

    log_tails

    while kill -0 "$APP_PID" 2>/dev/null; do
        sleep 60 &
        wait $! || true
        [ "$SHUTDOWN_REQUESTED" -eq 0 ] || break
        run_cron_hooks
    done

    if [ "$SHUTDOWN_REQUESTED" -ne 0 ]; then
        return 0
    fi

    local app_rc=0
    wait "$APP_PID" || app_rc=$?
    log "Application exited with status $app_rc. $(uptime_text)" "up.sh"
    return "$app_rc"
}

trap 'handle_signal SIGTERM' SIGTERM
trap 'handle_signal SIGINT' SIGINT
trap 'handle_signal SIGQUIT' SIGQUIT
trap on_exit EXIT

main
\t'/ }
        comm=${comm//
handle_signal() {
    local signal="$1"
    SHUTDOWN_REQUESTED=1
    log "Received $signal; beginning shutdown" "up.sh"
    stop_application
    exit 0
}

on_exit() {
    local rc=$?
    trap - EXIT
    stop_tailers
    if [ -n "${APP_PID_FILE:-}" ]; then
        rm -f "$APP_PID_FILE"
    fi
    exit "$rc"
}

main() {
    initialize_cron
    log_clean
    run_hooks "pre-startup"
    run_hooks "startup"
    build_command
    log_command

    local log_name="${APP_LOG_NAME:-${APP_EXE##*/}}"
    log_name="${log_name//\//_}"
    [ -n "$log_name" ] || log_name="application"

    mkdir -p "$(dirname "$APP_PID_FILE")" "$LOGS"
    rm -f "$APP_PID_FILE"

    # Bash starts asynchronous commands with SIGINT and SIGQUIT ignored when
    # job control is disabled. Reset those inherited dispositions before exec
    # so child images can use APP_STOP_SIGNAL=INT or QUIT reliably.
    setsid env --default-signal=INT --default-signal=QUIT -- "${APP_COMMAND_ARRAY[@]}" >> "$LOGS/$log_name.log" 2>&1 &
    APP_PID=$!
    APP_PGID=$APP_PID
    printf '%s\n' "$APP_PID" > "$APP_PID_FILE"

    sleep 1
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        local early_rc=0
        wait "$APP_PID" || early_rc=$?
        log "Application exited during startup verification with status $early_rc" "up.sh"
        return "$early_rc"
    fi

    log_tails

    while kill -0 "$APP_PID" 2>/dev/null; do
        sleep 60 &
        wait $! || true
        [ "$SHUTDOWN_REQUESTED" -eq 0 ] || break
        run_cron_hooks
    done

    if [ "$SHUTDOWN_REQUESTED" -ne 0 ]; then
        return 0
    fi

    local app_rc=0
    wait "$APP_PID" || app_rc=$?
    log "Application exited with status $app_rc. $(uptime_text)" "up.sh"
    return "$app_rc"
}

trap 'handle_signal SIGTERM' SIGTERM
trap 'handle_signal SIGINT' SIGINT
trap 'handle_signal SIGQUIT' SIGQUIT
trap on_exit EXIT

main
\n'/ }
        comm=${comm//
handle_signal() {
    local signal="$1"
    SHUTDOWN_REQUESTED=1
    log "Received $signal; beginning shutdown" "up.sh"
    stop_application
    exit 0
}

on_exit() {
    local rc=$?
    trap - EXIT
    stop_tailers
    if [ -n "${APP_PID_FILE:-}" ]; then
        rm -f "$APP_PID_FILE"
    fi
    exit "$rc"
}

main() {
    initialize_cron
    log_clean
    run_hooks "pre-startup"
    run_hooks "startup"
    build_command
    log_command

    local log_name="${APP_LOG_NAME:-${APP_EXE##*/}}"
    log_name="${log_name//\//_}"
    [ -n "$log_name" ] || log_name="application"

    mkdir -p "$(dirname "$APP_PID_FILE")" "$LOGS"
    rm -f "$APP_PID_FILE"

    # Bash starts asynchronous commands with SIGINT and SIGQUIT ignored when
    # job control is disabled. Reset those inherited dispositions before exec
    # so child images can use APP_STOP_SIGNAL=INT or QUIT reliably.
    setsid env --default-signal=INT --default-signal=QUIT -- "${APP_COMMAND_ARRAY[@]}" >> "$LOGS/$log_name.log" 2>&1 &
    APP_PID=$!
    APP_PGID=$APP_PID
    printf '%s\n' "$APP_PID" > "$APP_PID_FILE"

    sleep 1
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        local early_rc=0
        wait "$APP_PID" || early_rc=$?
        log "Application exited during startup verification with status $early_rc" "up.sh"
        return "$early_rc"
    fi

    log_tails

    while kill -0 "$APP_PID" 2>/dev/null; do
        sleep 60 &
        wait $! || true
        [ "$SHUTDOWN_REQUESTED" -eq 0 ] || break
        run_cron_hooks
    done

    if [ "$SHUTDOWN_REQUESTED" -ne 0 ]; then
        return 0
    fi

    local app_rc=0
    wait "$APP_PID" || app_rc=$?
    log "Application exited with status $app_rc. $(uptime_text)" "up.sh"
    return "$app_rc"
}

trap 'handle_signal SIGTERM' SIGTERM
trap 'handle_signal SIGINT' SIGINT
trap 'handle_signal SIGQUIT' SIGQUIT
trap on_exit EXIT

main
\r'/ }

        printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$ppid" "$pgrp" "$state" "$comm"
    done
}

log_application_group_snapshot() {
    local label="$1"
    local -a members=()
    local member pid ppid pgrp state comm

    mapfile -t members < <(application_group_members)
    APPLICATION_GROUP_SNAPSHOT_COUNT=${#members[@]}

    log "$label: pgid=$APP_PGID members=$APPLICATION_GROUP_SNAPSHOT_COUNT" "up.sh"
    for member in "${members[@]}"; do
        IFS=
handle_signal() {
    local signal="$1"
    SHUTDOWN_REQUESTED=1
    log "Received $signal; beginning shutdown" "up.sh"
    stop_application
    exit 0
}

on_exit() {
    local rc=$?
    trap - EXIT
    stop_tailers
    if [ -n "${APP_PID_FILE:-}" ]; then
        rm -f "$APP_PID_FILE"
    fi
    exit "$rc"
}

main() {
    initialize_cron
    log_clean
    run_hooks "pre-startup"
    run_hooks "startup"
    build_command
    log_command

    local log_name="${APP_LOG_NAME:-${APP_EXE##*/}}"
    log_name="${log_name//\//_}"
    [ -n "$log_name" ] || log_name="application"

    mkdir -p "$(dirname "$APP_PID_FILE")" "$LOGS"
    rm -f "$APP_PID_FILE"

    # Bash starts asynchronous commands with SIGINT and SIGQUIT ignored when
    # job control is disabled. Reset those inherited dispositions before exec
    # so child images can use APP_STOP_SIGNAL=INT or QUIT reliably.
    setsid env --default-signal=INT --default-signal=QUIT -- "${APP_COMMAND_ARRAY[@]}" >> "$LOGS/$log_name.log" 2>&1 &
    APP_PID=$!
    APP_PGID=$APP_PID
    printf '%s\n' "$APP_PID" > "$APP_PID_FILE"

    sleep 1
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        local early_rc=0
        wait "$APP_PID" || early_rc=$?
        log "Application exited during startup verification with status $early_rc" "up.sh"
        return "$early_rc"
    fi

    log_tails

    while kill -0 "$APP_PID" 2>/dev/null; do
        sleep 60 &
        wait $! || true
        [ "$SHUTDOWN_REQUESTED" -eq 0 ] || break
        run_cron_hooks
    done

    if [ "$SHUTDOWN_REQUESTED" -ne 0 ]; then
        return 0
    fi

    local app_rc=0
    wait "$APP_PID" || app_rc=$?
    log "Application exited with status $app_rc. $(uptime_text)" "up.sh"
    return "$app_rc"
}

trap 'handle_signal SIGTERM' SIGTERM
trap 'handle_signal SIGINT' SIGINT
trap 'handle_signal SIGQUIT' SIGQUIT
trap on_exit EXIT

main
\t' read -r pid ppid pgrp state comm <<< "$member"
        log "Process: pid=$pid ppid=$ppid pgid=$pgrp state=$state name=$comm" "up.sh"
    done
}

stop_application() {
    [ -n "${APP_PID:-}" ] || return 0
    application_group_alive || return 0

    run_hooks "shutdown" nonfatal

    local stop_signal=${APP_STOP_SIGNAL:-TERM}
    local timeout=${SHUTDOWN_TIMEOUT:-10}
    local waited=0

    log "Shutdown target: leader_pid=$APP_PID pgid=$APP_PGID signal=SIG$stop_signal timeout=${timeout}s" "up.sh"
    log_application_group_snapshot "Shutdown members"
    local initial_member_count=$APPLICATION_GROUP_SNAPSHOT_COUNT

    log "Stopping application process group $APP_PGID with SIG$stop_signal" "up.sh"
    kill -s "$stop_signal" -- "-$APP_PGID" 2>/dev/null || kill -s "$stop_signal" "$APP_PID" 2>/dev/null || true

    while application_group_alive && (( waited < timeout )); do
        sleep 1
        waited=$((waited + 1))
    done

    if application_group_alive; then
        log_application_group_snapshot "Processes remaining after ${timeout}s"
        log "Application process group did not stop within ${timeout}s; sending SIGKILL" "up.sh"
        kill -KILL -- "-$APP_PGID" 2>/dev/null || kill -KILL "$APP_PID" 2>/dev/null || true
    else
        log "Application process group stopped gracefully after ${waited}s; shutdown_start_process_count=$initial_member_count" "up.sh"
    fi
}

handle_signal() {
    local signal="$1"
    SHUTDOWN_REQUESTED=1
    log "Received $signal; beginning shutdown" "up.sh"
    stop_application
    exit 0
}

on_exit() {
    local rc=$?
    trap - EXIT
    stop_tailers
    if [ -n "${APP_PID_FILE:-}" ]; then
        rm -f "$APP_PID_FILE"
    fi
    exit "$rc"
}

main() {
    initialize_cron
    log_clean
    run_hooks "pre-startup"
    run_hooks "startup"
    build_command
    log_command

    local log_name="${APP_LOG_NAME:-${APP_EXE##*/}}"
    log_name="${log_name//\//_}"
    [ -n "$log_name" ] || log_name="application"

    mkdir -p "$(dirname "$APP_PID_FILE")" "$LOGS"
    rm -f "$APP_PID_FILE"

    # Bash starts asynchronous commands with SIGINT and SIGQUIT ignored when
    # job control is disabled. Reset those inherited dispositions before exec
    # so child images can use APP_STOP_SIGNAL=INT or QUIT reliably.
    setsid env --default-signal=INT --default-signal=QUIT -- "${APP_COMMAND_ARRAY[@]}" >> "$LOGS/$log_name.log" 2>&1 &
    APP_PID=$!
    APP_PGID=$APP_PID
    printf '%s\n' "$APP_PID" > "$APP_PID_FILE"

    sleep 1
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        local early_rc=0
        wait "$APP_PID" || early_rc=$?
        log "Application exited during startup verification with status $early_rc" "up.sh"
        return "$early_rc"
    fi

    log_tails

    while kill -0 "$APP_PID" 2>/dev/null; do
        sleep 60 &
        wait $! || true
        [ "$SHUTDOWN_REQUESTED" -eq 0 ] || break
        run_cron_hooks
    done

    if [ "$SHUTDOWN_REQUESTED" -ne 0 ]; then
        return 0
    fi

    local app_rc=0
    wait "$APP_PID" || app_rc=$?
    log "Application exited with status $app_rc. $(uptime_text)" "up.sh"
    return "$app_rc"
}

trap 'handle_signal SIGTERM' SIGTERM
trap 'handle_signal SIGINT' SIGINT
trap 'handle_signal SIGQUIT' SIGQUIT
trap on_exit EXIT

main
