#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/installers/hooks/pre-startup/10_steamcmd.sh"
TEST_ROOT="$(mktemp -d)"
STEAMCMD_PATH="$TEST_ROOT/steamcmd"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$STEAMCMD_PATH/linux32" "$STEAMCMD_PATH/linux64"
touch "$STEAMCMD_PATH/linux32/steamclient.so" "$STEAMCMD_PATH/linux64/steamclient.so"

run_hook() {
    local home="$1"
    local profile="$2"

    mkdir -p "$home"

    HOME="$home" \
    STEAMCMD_PROFILE="$profile" \
    STEAMCMD_PATH="$STEAMCMD_PATH" \
    STEAMCMD_EXEC=/bin/true \
    STEAM_SERVER_APPID=0 \
    STEAM_PLATFORM_TYPE=linux \
    APP_NAME=steamcmd-profile-test \
    APP_FILES="$TEST_ROOT/app" \
    UPDATE_ON_START=false \
    HOOK="$HOOK" \
    bash -c '
        set -Eeuo pipefail
        log() { :; }
        log_stdout() { cat >/dev/null; }
        source "$HOOK"
    '
}

fresh_home="$TEST_ROOT/fresh-home"
fresh_profile="$TEST_ROOT/fresh-profile"
run_hook "$fresh_home" "$fresh_profile"
[ -L "$fresh_home/Steam" ] || fail "fresh Steam home link was not created"
[ "$(realpath -m "$fresh_home/Steam")" = "$(realpath -m "$fresh_profile")" ] || fail "fresh Steam home link targets the wrong profile"
[ "$(readlink "$fresh_profile/sdk32/steamclient.so")" = "$STEAMCMD_PATH/linux32/steamclient.so" ] || fail "sdk32 link is incorrect"
[ "$(readlink "$fresh_profile/sdk64/steamclient.so")" = "$STEAMCMD_PATH/linux64/steamclient.so" ] || fail "sdk64 link is incorrect"
run_hook "$fresh_home" "$fresh_profile"

migrate_home="$TEST_ROOT/migrate-home"
migrate_profile="$TEST_ROOT/migrate-profile"
mkdir -p "$migrate_home/Steam/config" "$migrate_profile"
printf '%s\n' legacy > "$migrate_home/Steam/config/config.vdf"
printf '%s\n' retained > "$migrate_profile/existing-state"
run_hook "$migrate_home" "$migrate_profile"
[ -L "$migrate_home/Steam" ] || fail "migrated Steam directory was not replaced by a link"
grep -qx legacy "$migrate_profile/config/config.vdf" || fail "legacy Steam state was not migrated"
grep -qx retained "$migrate_profile/existing-state" || fail "existing persistent profile state was lost"

wrong_home="$TEST_ROOT/wrong-home"
wrong_profile="$TEST_ROOT/wrong-profile"
wrong_target="$TEST_ROOT/wrong-target"
mkdir -p "$wrong_home" "$wrong_target"
ln -s "$wrong_target" "$wrong_home/Steam"
if run_hook "$wrong_home" "$wrong_profile"; then
    fail "unexpected Steam home symlink was silently replaced"
fi
[ "$(realpath -m "$wrong_home/Steam")" = "$(realpath -m "$wrong_target")" ] || fail "unexpected Steam home symlink was modified"

direct_home="$TEST_ROOT/direct-home"
direct_profile="$direct_home/Steam"
mkdir -p "$direct_profile"
run_hook "$direct_home" "$direct_profile"
[ -d "$direct_profile" ] && [ ! -L "$direct_profile" ] || fail "direct Steam profile path should remain a directory"
[ -L "$direct_profile/sdk32/steamclient.so" ] || fail "direct profile sdk32 link missing"
[ -L "$direct_profile/sdk64/steamclient.so" ] || fail "direct profile sdk64 link missing"

echo "SteamCMD profile contract tests passed"
