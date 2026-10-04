#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WINE_HOOK="$REPO_ROOT/installers/hooks/pre-startup/20_wine_prefix.sh"
PROTON_HOOK="$REPO_ROOT/installers/hooks/pre-startup/20_proton_prefix.sh"
TEST_ROOT="$(mktemp -d)"
MOCK_BIN="$TEST_ROOT/bin"
mkdir -p "$MOCK_BIN"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

cat > "$MOCK_BIN/xvfb-run" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
while [ "$#" -gt 0 ]; do
    case "$1" in
        --auto-servernum|--server-args=*)
            shift
            ;;
        *)
            break
            ;;
    esac
done
exec "$@"
EOF

cat > "$MOCK_BIN/wineboot" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'wineboot\n' >> "$MOCK_COUNTER"
mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
printf 'registry\n' > "$WINEPREFIX/system.reg"
touch "$WINEPREFIX/drive_c/windows/syswow64/regedit.exe"
if [ "${MOCK_FAIL_PREFIX:-0}" = "1" ]; then
    exit 17
fi
EOF

cat > "$MOCK_BIN/wine" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[ "${1:-}" = "cmd" ] || exit 2
exit 0
EOF

cat > "$MOCK_BIN/proton" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[ "${1:-}" = "runinprefix" ] || exit 2
shift
case "${1:-}" in
    wineboot)
        printf 'proton-wineboot\n' >> "$MOCK_COUNTER"
        mkdir -p "$WINEPREFIX/pfx"
        printf 'registry\n' > "$WINEPREFIX/pfx/system.reg"
        if [ "${MOCK_FAIL_PREFIX:-0}" = "1" ]; then
            exit 17
        fi
        ;;
    cmd)
        exit 0
        ;;
    *)
        exit 2
        ;;
esac
EOF

chmod 0755 "$MOCK_BIN/xvfb-run" "$MOCK_BIN/wineboot" "$MOCK_BIN/wine" "$MOCK_BIN/proton"

run_hook() {
    local hook="$1"
    local prefix="$2"
    local counter="$3"
    local fail_prefix="${4:-0}"

    PATH="$MOCK_BIN:$PATH"     WINEPREFIX="$prefix"     WINEARCH=wow64     COMPAT_COMMAND=wine     ARCH_COMMAND_PREFIX=""     COMPAT_PREFIX_TIMEOUT=5     MOCK_COUNTER="$counter"     MOCK_FAIL_PREFIX="$fail_prefix"     HOOK="$hook"     bash -c '
        set -Eeuo pipefail
        log() { :; }
        log_stdout() { cat >/dev/null; }
        source "$HOOK"
    '
}

wine_prefix="$TEST_ROOT/wine-prefix"
wine_counter="$TEST_ROOT/wine-counter"
mkdir -p "$wine_prefix"
touch "$wine_prefix/partial-file"
run_hook "$WINE_HOOK" "$wine_prefix" "$wine_counter"
[ -f "$wine_prefix/.steamcmd-server-wine-ready" ] || fail "Wine readiness marker was not created"
[ "$(wc -l < "$wine_counter")" -eq 1 ] || fail "Wine initialization did not run exactly once"
run_hook "$WINE_HOOK" "$wine_prefix" "$wine_counter"
[ "$(wc -l < "$wine_counter")" -eq 1 ] || fail "Ready Wine prefix was initialized again"

wine_failed="$TEST_ROOT/wine-failed"
wine_failed_counter="$TEST_ROOT/wine-failed-counter"
mkdir -p "$wine_failed"
if run_hook "$WINE_HOOK" "$wine_failed" "$wine_failed_counter" 1; then
    fail "Failed Wine initialization was reported as successful"
fi
[ ! -e "$wine_failed/.steamcmd-server-wine-ready" ] || fail "Failed Wine initialization wrote a readiness marker"

proton_prefix="$TEST_ROOT/proton-prefix"
proton_counter="$TEST_ROOT/proton-counter"
mkdir -p "$proton_prefix"
touch "$proton_prefix/partial-file"
run_hook "$PROTON_HOOK" "$proton_prefix" "$proton_counter"
[ -f "$proton_prefix/.steamcmd-server-proton-ready" ] || fail "Proton readiness marker was not created"
[ "$(wc -l < "$proton_counter")" -eq 1 ] || fail "Proton initialization did not run exactly once"
run_hook "$PROTON_HOOK" "$proton_prefix" "$proton_counter"
[ "$(wc -l < "$proton_counter")" -eq 1 ] || fail "Ready Proton prefix was initialized again"

proton_failed="$TEST_ROOT/proton-failed"
proton_failed_counter="$TEST_ROOT/proton-failed-counter"
mkdir -p "$proton_failed"
if run_hook "$PROTON_HOOK" "$proton_failed" "$proton_failed_counter" 1; then
    fail "Failed Proton initialization was reported as successful"
fi
[ ! -e "$proton_failed/.steamcmd-server-proton-ready" ] || fail "Failed Proton initialization wrote a readiness marker"

echo "Compatibility prefix hook tests passed"
