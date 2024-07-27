FROM ghcr.io/teriyakidactyl/docker-steamcmd-server:latest

# docker-steamcmd-server required ENVS
ENV \
    # Application Info
    APP_EXE="ConanSandboxServer.exe" \
    \
    # Steam specific paths / IDS
    \
    STEAM_ALLOW_LIST_PATH="$WORLD_FILES/Saved/whitelist.txt" \
    STEAM_SERVER_APPID="443030" \
    STEAM_APPID="440900"

# Potential example server variables
ENV \
    APP_NAME="conan" \
    SERVER_PLAYER_PASS="MySecretPassword" \
    SERVER_ADMIN_PASS="MySecretPasswordAdmin" \
    SERVER_NAME="Teriyakolypse"