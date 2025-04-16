#!/bin/bash

# TODO UDP process monitor https://github.com/lloesche/valheim-server-docker/blob/0996dc3a1fc1f5f88bcbd4056a28254adadb884e/common#L148
# TODO RCON Configuration https://conanexiles.fandom.com/wiki/Rcon
# TODO RCON 'Attach' mode
# TODO add 'server' restart interval and ENV support

# Server update function - handles SteamCMD game updates
gameserver_update() {
    log "Starting server update for $APP_NAME" "update"
    
    # Set SteamCMD environment variables
    export LD_LIBRARY_PATH="$STEAMCMD_PATH/linux32"
    
    # Initialize SteamCMD if needed
    if [ ! -d "$STEAMCMD_PROFILE" ]; then
        log "$STEAMCMD_PATH directory not complete, presuming first run." "update"
        $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit | log_stdout "steamcmd"
    fi
    
    # Set platform type (windows/linux) based on game requirements
    # Default to linux, but can be overridden with STEAM_PLATFORM_TYPE env var
    local platform_type="${STEAM_PLATFORM_TYPE:-linux}"
    
    # Update the server
    log "SteamCMD beginning download of $APP_NAME (AppID: $STEAM_SERVER_APPID)" "update"
    $STEAMCMD_PATH/steamcmd.sh \
        +@sSteamCmdForcePlatformType $platform_type \
        +force_install_dir $APP_FILES \
        +login anonymous \
        +app_update $STEAM_SERVER_APPID \
        validate \
        +quit | log_stdout "steamcmd"
        
    log "Server update completed" "update"
}

# Server start function
gameserver_start() {
    # Display server configuration
    log "+----------------------------------+"
    log "Server configuration:"
    log "APP_NAME: $APP_NAME"
    log "APP_EXE: $APP_EXE"
    log "SERVER_NAME: $SERVER_NAME"
    
    # Log extra variables if they exist
    [ -n "$SERVER_PASSWORD" ] && log "SERVER_PASSWORD: [password hidden]"
    [ -n "$SERVER_PASS" ] && log "SERVER_PASS: [password hidden]"
    [ -n "$WORLD_NAME" ] && log "WORLD_NAME: $WORLD_NAME"
    [ -n "$SERVER_PUBLIC" ] && log "SERVER_PUBLIC: $SERVER_PUBLIC"
    [ -n "$SERVER_PORT" ] && log "SERVER_PORT: $SERVER_PORT"
    log "+----------------------------------+"
    
    # Set game-specific environment variables if needed
    # Add any game-specific environment variables here
    # For example: export LD_LIBRARY_PATH=$APP_FILES/linux64
    
    # Set command to execute the server with APP_ARGS
    # The base COMMAND includes just the executable path
    # Architecture-specific prefixes will be handled by the caller (up.sh)
    # APP_COMMAND_PREFIX should be generated in DOCKER build, like APP_COMMAND_PREFIX="box64 wine" or "box64" or "wine"
    APP_COMMAND="$APP_COMMAND_PREFIX $APP_FILES/$APP_EXE"
    
    # Log the server startup
    log "Starting $APP_NAME server..." "server"
    
    # Execute the command with arguments and proper output redirection
    # This uses APP_ARGS which should be set in the Dockerfile
    eval "$APP_COMMAND $APP_ARGS >> $LOGS/$APP_NAME.log 2>&1 &"
    
    # Record the process ID
    sleep 1
    export APP_PID=$!
    log "Started $APP_NAME server with PID $APP_PID" "server"
    
    # Additional startup tasks can be added here
}

gameserver_needs_update() {
    local STEAM_SERVER_APPID=$1
    local API_URL="https://api.steamcmd.net/v1/info/$STEAM_SERVER_APPID"
    local MANIFEST_FILE="$APP_FILES/steamapps/appmanifest_${STEAM_CON_SERVER_APPID}.acf"

    # TODO log local and remote version
    # Don't refference ENV, refference local?

    # Get buildid from API
    local API_BUILDID=$(curl -s "$API_URL" | grep -oP '"public":\s*\{\s*"buildid":\s*"\K[^"]+')

    # Get buildid from local manifest
    local LOCAL_BUILDID=$(grep -oP '"buildid"\s+"\K[^"]+' "$MANIFEST_FILE")

    # Compare buildids
    if [[ "$API_BUILDID" > "$LOCAL_BUILDID" ]]; then
        echo "Update Needed"
        return 0  # True, update needed
    else
        echo "Undate not Needed"
        return 1  # False, no update needed
    fi
}

# Check and process whitelist/allowlist if specified
check_whitelist() {
    # Skip if no allow list or path not specified
    if [ -z "$SERVER_ALLOW_LIST" ] || [ -z "$STEAM_ALLOW_LIST_PATH" ]; then
        return 0
    fi
    
    log "Processing server allow list" "whitelist"
    
    # Remove existing whitelist file if it exists
    if [ -f "$STEAM_ALLOW_LIST_PATH" ]; then
        rm "$STEAM_ALLOW_LIST_PATH" || { 
            log "Failed to remove existing whitelist file: $STEAM_ALLOW_LIST_PATH" "whitelist"
            return 1
        }
    fi
    
    # Create directory for allowlist if it doesn't exist
    mkdir -p "$(dirname "$STEAM_ALLOW_LIST_PATH")"
    
    # Create an empty whitelist file
    touch "$STEAM_ALLOW_LIST_PATH" || { 
        log "Failed to create whitelist file: $STEAM_ALLOW_LIST_PATH" "whitelist"
        return 1
    }
    
    # Populate whitelist file with STEAM_IDs
    IFS=", " read -r -a STEAM_IDS <<< "$SERVER_ALLOW_LIST"
    for STEAM_ID in "${STEAM_IDS[@]}"; do
        echo "$STEAM_ID" >> "$STEAM_ALLOW_LIST_PATH" || { 
            log "Failed to write to whitelist file: $STEAM_ALLOW_LIST_PATH" "whitelist"
            return 1
        }
    done
    
    log "Allow list created with ${#STEAM_IDS[@]} entries" "whitelist"
    
    # Enable whitelist in server configuration if required
    if type update_config_element &>/dev/null; then
        update_config_element "EnableWhitelist" "True"
    fi
}

check_env() {

    if [[ ${#SERVER_PLAYER_PASS} -lt 5 ]]; then
        log "WARNING - Password: '$SERVER_PLAYER_PASS' too short! Password should be at least 5 characters long."
    fi

    if [[ "$SERVER_NAME" == *"$SERVER_PLAYER_PASS"* ]]; then
        log "WARNING - Password '$SERVER_PLAYER_PASS' should not be part of the server name."
    fi
}

mod_updates() {
    
    # https://forums.funcom.com/t/conan-exiles-dedicated-server-launcher-official-version-1-7-8-beta-1-7-9/21699#mods
    # force_install_dir "$WORLD_FILES/Mods" > /Mods/steamapps/workshop/conent/$MOD_ID

    # mod_updates(): Manages mods for Conan Exiles server
    # - Downloads specified mods via SteamCMD
    # - Removes unspecified mods
    # - Updates modlist.txt
    # Logic:
    # 1. If mods specified:
    #    - Download each mod
    #    - Link .pak files to server mod directory
    #    - Remove obsolete mods
    #    - Update modlist.txt
    # 2. If no mods: Clear mod directory, create empty modlist.txt

    # Mod Updates
    if [ -n "$SERVER_MOD_IDS" ]; then
        # Create an array of current mod IDs
        IFS=',' read -ra MOD_IDS <<< "$SERVER_MOD_IDS"
        rm -rd /world/Mods/*
        # Download and update mods
        for MOD_ID in "${MOD_IDS[@]}"; do
            log "Downloading mod with ID: $MOD_ID"
            $STEAMCMD_PATH/steamcmd.sh \
            +force_install_dir "$STEAM_LIBRARY" \
            +login anonymous \
            +workshop_download_item $STEAM_CONAN_CLIENT_APPID $MOD_ID \
            +quit | log_stdout
            find "$STEAM_LIBRARY" -path "*$MOD_ID*.pak" -exec ln -sf {} /world/Mods \; 
        done

        # Remove mods that are no longer in the list
        for MOD_DIR in "$WORLD_FILES/Mods"/*; do
            if [ -d "$MOD_DIR" ]; then
                MOD_ID=$(basename "$MOD_DIR")
                if ! [[ " ${MOD_IDS[@]} " =~ " ${MOD_ID} " ]]; then
                    log "Removing mod with ID: $MOD_ID"
                    rm -rf "$MOD_DIR"
                fi
            fi
        done

        # Create the modlist.txt file
        # FIXME this implementation is probably Conan Specific
        find "$WORLD_FILES/Mods" -type l -name "*.pak" -exec basename {} \; | sed 's/^/*/' > "$WORLD_FILES/Mods/modlist.txt"
        log "Mods enabled: "
        cat $WORLD_FILES/Mods/modlist.txt | log_stdout
    else
        rm -rf $WORLD_FILES/Mods/*
        > "$WORLD_FILES/Mods/modlist.txt"  # Create empty modlist.txt
    fi

}

# Generic update_config_element function (can be overridden by game-specific implementation)
update_config_element() {
    local KEY=$1
    local VALUE=$2
    
    log "Setting config: $KEY=$VALUE" "config"
    
    # Game-specific configuration should override this function
    # This is just a placeholder implementation
    log "Note: Generic configuration function used. Game-specific implementation recommended." "config"
}

wine_setup (){

    # https://wiki.winehq.org/FAQ#Is_there_a_64_bit_Wine , https://wiki.winehq.org/FAQ#How_do_I_create_a_32_bit_wineprefix_on_a_64_bit_system?
    # It requires the installation of 32 bit libraries in order to run 32 bit Windows applications

    # Check first time wine run, this will force Wine config creation so that our server load won't fail on first run.
    if [ ! -d "$WINEPREFIX" ]; then
        # https://wiki.winehq.org/Wineboot
        log "First run detected, wait 15 seconds for wine config creation."
        wine wineboot -iuf | log_stdout
        fi
    fi
}

