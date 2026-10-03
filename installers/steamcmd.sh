#!/usr/bin/env bash

set -Eeuo pipefail

: "${STEAMCMD_PATH:?STEAMCMD_PATH is required}"
: "${STEAMCMD_EXEC:?STEAMCMD_EXEC is required}"
: "${STEAMCMD_PROFILE:?STEAMCMD_PROFILE is required}"
: "${CONTAINER_USER:?CONTAINER_USER is required}"

mkdir -p "$STEAMCMD_PATH" "$STEAMCMD_PROFILE/sdk32" "$STEAMCMD_PROFILE/sdk64"

tmp_archive="$(mktemp)"
curl --fail --show-error --silent --location \
    --retry 5 --retry-all-errors --connect-timeout 15 \
    "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
    --output "$tmp_archive"

tar -xzf "$tmp_archive" -C "$STEAMCMD_PATH"
rm -f "$tmp_archive"

ln -sf "$STEAMCMD_PATH/linux32/steamclient.so" "$STEAMCMD_PROFILE/sdk32/steamclient.so"
ln -sf "$STEAMCMD_PATH/linux64/steamclient.so" "$STEAMCMD_PROFILE/sdk64/steamclient.so"

if [ "$TARGETARCH" = "arm64" ]; then
    cat > "$STEAMCMD_EXEC" <<'EOF'
#!/bin/bash
set -e
cd /opt/steamcmd

# Valve's launcher handles SteamCMD's magic exit code 42 by relaunching after a
# self-update. Keep that restart contract on arm64 while forcing the packaged
# 32-bit client through Box86; the installer archive does not provision a
# linuxarm64 bootstrap.
export STEAM_PLATFORM=linux32
export DEBUGGER=box86
exec /opt/steamcmd/steamcmd.sh "$@"
EOF
else
    cat > "$STEAMCMD_EXEC" <<'EOF'
#!/bin/bash
set -e
cd /opt/steamcmd
exec /opt/steamcmd/steamcmd.sh "$@"
EOF
fi
chmod 0755 "$STEAMCMD_EXEC"
chown root:root "$STEAMCMD_EXEC"
chown -R "$CONTAINER_USER:$CONTAINER_USER" "$STEAMCMD_PATH" "$STEAMCMD_PROFILE"

mkdir -p "$HOOK_DIRECTORIES/pre-startup"
install -m 0755 /tmp/installers/hooks/pre-startup/10_steamcmd.sh \
    "$HOOK_DIRECTORIES/pre-startup/10_steamcmd.sh"
chown root:root "$HOOK_DIRECTORIES/pre-startup/10_steamcmd.sh"
