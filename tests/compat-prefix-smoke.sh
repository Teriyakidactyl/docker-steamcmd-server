#!/usr/bin/env bash

set -Eeuo pipefail

IMAGE="${1:?image reference is required}"
PLATFORM="${2:?platform is required}"
COMPAT_LAYER_TYPE="${3:?compatibility layer type is required}"

case "$COMPAT_LAYER_TYPE" in
    wine|proton) ;;
    *)
        echo "Unsupported compatibility layer type: $COMPAT_LAYER_TYPE" >&2
        exit 2
        ;;
esac

TEST_ROOT="$(mktemp -d)"
CONTAINER_NAME="compat-prefix-smoke-${GITHUB_RUN_ID:-local}-$$-$RANDOM"
LOG_FILE="$TEST_ROOT/container.log"

cleanup() {
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

set +e
timeout --signal=TERM --kill-after=15s 420s \
    docker run \
        --name "$CONTAINER_NAME" \
        --platform "$PLATFORM" \
        -e UPDATE_ON_START=false \
        -e COMPAT_PREFIX_TIMEOUT=180 \
        -e STEAM_SERVER_APPID=0 \
        -e APP_NAME=compat-prefix-smoke \
        -e APP_COMMAND=/bin/true \
        "$IMAGE" >"$LOG_FILE" 2>&1
run_rc=$?
set -e

cat "$LOG_FILE"

if [ "$run_rc" -ne 0 ]; then
    echo "::error::Compatibility prefix smoke exited $run_rc" >&2
    docker inspect "$CONTAINER_NAME" \
        --format 'status={{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}' \
        2>/dev/null || true
    exit "$run_rc"
fi

assert_container_file() {
    local path="$1"
    local destination="$2"
    local description="$3"

    if ! docker cp "$CONTAINER_NAME:$path" "$destination" >/dev/null 2>&1; then
        echo "::error::Missing $description at $path" >&2
        return 1
    fi
}

case "$COMPAT_LAYER_TYPE" in
    wine)
        assert_container_file \
            /app/.compat/wine/.steamcmd-server-wine-ready \
            "$TEST_ROOT/wine-ready" \
            "Wine readiness marker"
        assert_container_file \
            /app/.compat/wine/system.reg \
            "$TEST_ROOT/wine-system.reg" \
            "Wine system registry"
        assert_container_file \
            /app/.compat/wine/drive_c/windows/syswow64/regedit.exe \
            "$TEST_ROOT/wine-syswow64-regedit.exe" \
            "Wine WoW64 regedit.exe"
        test -s "$TEST_ROOT/wine-system.reg"
        ;;
    proton)
        assert_container_file \
            /app/.compat/proton/.steamcmd-server-proton-ready \
            "$TEST_ROOT/proton-ready" \
            "Proton readiness marker"
        assert_container_file \
            /app/.compat/proton/pfx/system.reg \
            "$TEST_ROOT/proton-system.reg" \
            "Proton system registry"
        test -s "$TEST_ROOT/proton-system.reg"
        ;;
esac

echo "$COMPAT_LAYER_TYPE compatibility prefix smoke passed"
