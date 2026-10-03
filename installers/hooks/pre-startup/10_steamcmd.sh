#!/bin/bash

REQUIRED_VARS=("STEAM_SERVER_APPID" "STEAM_PLATFORM_TYPE" "APP_NAME" "APP_FILES")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        log "ERROR: required environment variable '$var' is not set" "10_steamcmd.sh"
        return 1
    fi
done

if [ "${UPDATE_ON_START:-true}" != "true" ]; then
    log "SteamCMD update skipped because UPDATE_ON_START=${UPDATE_ON_START:-false}" "10_steamcmd.sh"
    return 0
fi

mkdir -p "$APP_FILES"

declare -a update_args=(
    +@ShutdownOnFailedCommand 1
    +@NoPromptForPassword 1
    +@sSteamCmdForcePlatformType "$STEAM_PLATFORM_TYPE"
    +force_install_dir "$APP_FILES"
    +login anonymous
    +app_update "$STEAM_SERVER_APPID"
)

if [ "${STEAM_VALIDATE:-false}" = "true" ]; then
    update_args+=(validate)
fi
update_args+=(+quit)

retries="${STEAMCMD_RETRIES:-5}"
attempt=1
success=0
output_file="$(mktemp)"

while (( attempt <= retries )); do
    : > "$output_file"
    log "SteamCMD update attempt $attempt/$retries for $APP_NAME ($STEAM_SERVER_APPID)" "10_steamcmd.sh"

    if "$STEAMCMD_EXEC" "${update_args[@]}" 2>&1 | tee "$output_file" | log_stdout "10_steamcmd.sh"; then
        if grep -Eq "Success! App '?${STEAM_SERVER_APPID}'? (fully installed|already up to date)" "$output_file"; then
            success=1
            break
        fi
        log "SteamCMD exited successfully but did not report a successful app update" "10_steamcmd.sh"
    else
        log "SteamCMD command failed" "10_steamcmd.sh"
    fi

    attempt=$((attempt + 1))
    if (( attempt <= retries )); then
        sleep 5
    fi
done

rm -f "$output_file"

if [ "$success" -ne 1 ]; then
    log "ERROR: SteamCMD failed after $retries attempts" "10_steamcmd.sh"
    return 1
fi

log "SteamCMD update completed successfully" "10_steamcmd.sh"
