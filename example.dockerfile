# Valheim Server - Example Derivative Container
# Based on docker-steamcmd-server
#
# This Dockerfile demonstrates how to create a game server container
# that leverages the docker-steamcmd-server base image.
#
# The base image provides:
# - SteamCMD for installing and updating the game server
# - Architecture detection (x86_64/ARM64)
# - Compatibility layers (Wine, Box86/Box64)
# - Server monitoring and logging
# - Automatic updates

FROM ghcr.io/teriyakidactyl/docker-steamcmd-server:latest

# Game-specific environment variables (required)
ENV \
    APP_NAME="valheim" \
    APP_EXE="valheim_server.x86_64" \
    STEAM_SERVER_APPID="896660" \
    STEAM_PLATFORM_TYPE="linux" \
    STEAM_ALLOW_LIST_PATH=""

# Server configuration variables (optional/customizable)
ENV \
    # Server settings
    SERVER_NAME="Docker Valheim Server" \
    SERVER_PASSWORD="secret" \
    SERVER_PUBLIC="1" \
    SERVER_PORT="2456" \
    WORLD_NAME="DockerWorld"

# Command line arguments for the server
# Each argument on its own line for readability
ENV APP_ARGS="\
-nographics \
-batchmode \
-name \"$SERVER_NAME\" \
-port $SERVER_PORT \
-public $SERVER_PUBLIC \
-world \"$WORLD_NAME\" \
-password \"$SERVER_PASSWORD\" \
-savedir \"$WORLD_FILES\" \
-saveinterval 1800"

# Additional configuration paths
ENV \
    STEAM_ALLOW_LIST_PATH="${WORLD_FILES}/adminlist.txt" \
    SERVER_CONFIG_PATH="${WORLD_FILES}/config" \
    SERVER_SAVE_PATH="${WORLD_FILES}/saves"

# Create necessary server initialization script
COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} server_functions.sh ${SCRIPTS}/

# Ports used by the Valheim server
EXPOSE 2456-2458/udp

# Volumes for persistent data and application files
VOLUME ["${WORLD_FILES}"]
VOLUME ["${APP_FILES}"]

# Use the base container's up.sh script directly
CMD ["up.sh"]