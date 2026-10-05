#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPERVISOR="$REPO_ROOT/runtime/container/up.sh"
TEST_ROOT="$(mktemp -d)"
SCRIPTS_ROOT="$TEST_ROOT/scripts"
HOOK_ROOT="$TEST_ROOT/hooks"
SUPERVISOR_PID=""

mkdir -p "$SCRIPTS_ROOT/container" "$HOOK_ROOT"

cleanup() {
    if [ -n "$SUPERVISOR_PID" ] && kill -0 "$SUPERVISOR_PID" 2>/dev/null; then
        kill -KILL "$SUPERVISOR_PID" 2>/dev/null || true
        wait "$SUPERVISOR_PID" 2>/dev/null || true
    fi

    local pid_file
    while IFS= read -r pid_file; do
        if [ -s "$pid_file" ]; then
            local pgid
            pgid="$(cat "$pid_file")"
            kill -KILL -- "-$pgid" 2>/dev/null || true
        fi
    done < <(find "$TEST_ROOT" -name app.pid -type f 2>/dev/null)

    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

wait_for_file() {
    local path="$1"
    local attempts=0
    while [ ! -s "$path" ] && (( attempts < 100 )); do
        sleep 0.05
        attempts=$((attempts + 1))
    done
    [ -s "$path" ] || fail "Timed out waiting for $path"
}

snapshot_member_count() {
    local label="$1"
    local log_file="$2"
    local line count

    line="$(grep -F "$label:" "$log_file" | tail -1 || true)"
    count="${line##* members=}"
    [[ "$count" =~ ^[0-9]+$ ]] || fail "Could not parse member count for $label"
    printf '%s\n' "$count"
}

cat > "$SCRIPTS_ROOT/container/logging.sh" <<'EOF'
#!/usr/bin/env bash

log() {
    printf '%s\n' "$1" >> "$SUPERVISOR_LOG"
}

log_clean() {
    :
}

log_tails() {
    :
}
EOF
chmod 0755 "$SCRIPTS_ROOT/container/logging.sh"

run_supervisor() {
    local case_root="$1"
    local executable="$2"
    local stop_signal="$3"
    local shutdown_timeout="$4"

    mkdir -p "$case_root/logs"
    : > "$case_root/supervisor.log"

    SCRIPTS="$SCRIPTS_ROOT" \
    HOOK_DIRECTORIES="$HOOK_ROOT" \
    LOGS="$case_root/logs" \
    APP_NAME="shutdown-test" \
    APP_EXE="" \
    APP_EXECUTABLE="$executable" \
    APP_PID_FILE="$case_root/app.pid" \
    APP_STOP_SIGNAL="$stop_signal" \
    SHUTDOWN_TIMEOUT="$shutdown_timeout" \
    LOG_UPTIME=false \
    SUPERVISOR_LOG="$case_root/supervisor.log" \
    TEST_TRACE="$case_root/trace.log" \
    TEST_CHILD_PID_FILE="$case_root/child.pid" \
    bash "$SUPERVISOR" &

    SUPERVISOR_PID=$!
    wait_for_file "$case_root/app.pid"
}

graceful_root="$TEST_ROOT/graceful"
mkdir -p "$graceful_root"
cat > "$graceful_root/app.sh" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

: > "$TEST_TRACE"

(
    trap 'trap "" INT TERM; printf "child-int\n" >> "$TEST_TRACE"; sleep 2; printf "child-exit\n" >> "$TEST_TRACE"; exit 0' INT
    trap 'trap "" INT TERM; printf "child-term\n" >> "$TEST_TRACE"; exit 0' TERM
    printf '%s\n' "$BASHPID" > "$TEST_CHILD_PID_FILE"
    while :; do
        sleep 30
    done
) &

trap 'printf "leader-int\n" >> "$TEST_TRACE"; exit 0' INT
trap 'printf "leader-term\n" >> "$TEST_TRACE"; exit 0' TERM

while :; do
    sleep 30
done
EOF
chmod 0755 "$graceful_root/app.sh"

run_supervisor "$graceful_root" "$graceful_root/app.sh" INT 5
wait_for_file "$graceful_root/child.pid"

kill -TERM "$SUPERVISOR_PID"
wait "$SUPERVISOR_PID"
SUPERVISOR_PID=""
printf 'supervisor-exit\n' >> "$graceful_root/trace.log"

grep -Fqx 'leader-int' "$graceful_root/trace.log" || fail "Configured SIGINT did not reach the application leader"
grep -Fqx 'child-int' "$graceful_root/trace.log" || fail "Configured SIGINT did not reach the application child"
if grep -Fq -- '-term' "$graceful_root/trace.log"; then
    fail "Application received SIGTERM instead of configured SIGINT"
fi

child_exit_line="$(grep -Fn 'child-exit' "$graceful_root/trace.log" | cut -d: -f1)"
supervisor_exit_line="$(grep -Fn 'supervisor-exit' "$graceful_root/trace.log" | cut -d: -f1)"
[ -n "$child_exit_line" ] || fail "Application child did not finish graceful cleanup"
[ "$child_exit_line" -lt "$supervisor_exit_line" ] || fail "Supervisor exited before the application process group finished"
grep -Fq 'Shutdown target: leader_pid=' "$graceful_root/supervisor.log" ||
    fail "Shutdown target metadata was not logged"
graceful_members="$(snapshot_member_count 'Shutdown members' "$graceful_root/supervisor.log")"
[ "$graceful_members" -ge 2 ] ||
    fail "Expected at least leader and child in graceful shutdown snapshot"
grep -Eq "^Process: pid=[0-9]+ ppid=[0-9]+ pgid=[0-9]+ state=[A-Za-z] name=.+" "$graceful_root/supervisor.log" ||
    fail "Per-process shutdown metadata was not logged"
grep -Fq 'Application process group stopped gracefully' "$graceful_root/supervisor.log" ||
    fail "Graceful process-group completion was not logged"
grep -Fq "shutdown_start_process_count=$graceful_members" "$graceful_root/supervisor.log" ||
    fail "Graceful completion did not report the starting process count"

forced_root="$TEST_ROOT/forced"
mkdir -p "$forced_root"
cat > "$forced_root/app.sh" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

trap '' INT TERM
while :; do
    sleep 30
done
EOF
chmod 0755 "$forced_root/app.sh"

run_supervisor "$forced_root" "$forced_root/app.sh" INT 1
kill -TERM "$SUPERVISOR_PID"
wait "$SUPERVISOR_PID"
SUPERVISOR_PID=""

forced_start_members="$(snapshot_member_count 'Shutdown members' "$forced_root/supervisor.log")"
[ "$forced_start_members" -ge 1 ] ||
    fail "Forced shutdown snapshot did not contain an application process"
forced_remaining="$(snapshot_member_count 'Processes remaining after 1s' "$forced_root/supervisor.log")"
[ "$forced_remaining" -ge 1 ] ||
    fail "Forced shutdown did not log surviving processes"
grep -Fq 'Application process group did not stop within 1s; sending SIGKILL' "$forced_root/supervisor.log" ||
    fail "Forced process-group shutdown was not logged"

echo "Supervisor shutdown lifecycle tests passed"
