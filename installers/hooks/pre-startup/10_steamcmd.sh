#!/bin/bash

REQUIRED_VARS=("STEAM_SERVER_APPID" "STEAM_PLATFORM_TYPE" "APP_NAME" "APP_FILES" "STEAMCMD_PATH" "STEAMCMD_EXEC" "STEAMCMD_PROFILE" "HOME")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        log "ERROR: required environment variable '$var' is not set" "10_steamcmd.sh"
        return 1
    fi
done

ensure_steamcmd_profile() {
    local steam_home="$HOME/Steam"
    local profile_path
    local steam_home_path
    local current_target
    local current_target_path

    profile_path="$(realpath -m "$STEAMCMD_PROFILE")"
    steam_home_path="$(realpath -m "$steam_home")"

    mkdir -p "$profile_path"

    if [ "$profile_path" != "$steam_home_path" ]; then
        case "$profile_path/" in
            "$steam_home_path/"*)
                log "ERROR: STEAMCMD_PROFILE may not be inside $steam_home" "10_steamcmd.sh"
                return 1
                ;;
        esac

        if [ -L "$steam_home" ]; then
            current_target="$(readlink "$steam_home")"
            if [[ "$current_target" = /* ]]; then
                current_target_path="$(realpath -m "$current_target")"
            else
                current_target_path="$(realpath -m "$(dirname "$steam_home")/$current_target")"
            fi

            if [ "$current_target_path" != "$profile_path" ]; then
                log "ERROR: $steam_home already points to $current_target; expected $profile_path" "10_steamcmd.sh"
                return 1
            fi
        elif [ -e "$steam_home" ]; then
            if [ ! -d "$steam_home" ]; then
                log "ERROR: $steam_home exists but is not a directory or symlink" "10_steamcmd.sh"
                return 1
            fi

            log "Migrating Steam client state from $steam_home to $profile_path" "10_steamcmd.sh"
            cp -a "$steam_home/." "$profile_path/"
            rm -rf "$steam_home"
            ln -s "$profile_path" "$steam_home"
        else
            mkdir -p "$(dirname "$steam_home")"
            ln -s "$profile_path" "$steam_home"
        fi
    fi

    mkdir -p "$profile_path/sdk32" "$profile_path/sdk64"
    ln -sfn "$STEAMCMD_PATH/linux32/steamclient.so" "$profile_path/sdk32/steamclient.so"
    ln -sfn "$STEAMCMD_PATH/linux64/steamclient.so" "$profile_path/sdk64/steamclient.so"

    log "SteamCMD profile is ready at $profile_path" "10_steamcmd.sh"
}

ensure_steamcmd_profile

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
