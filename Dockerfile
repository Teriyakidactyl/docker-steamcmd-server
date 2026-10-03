ARG DEBIAN_TAG

FROM debian:${DEBIAN_TAG}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG TARGETPLATFORM
ARG DEBIAN_VERSION_CODENAME
ARG SOURCE_COMMIT
ARG BUILD_DATE
ARG BUILD_VERSION
ARG CONTAINER_UID=1000
ARG DOCKER_UP_REF=1e44675134a030531fb4744dc835fac5f53b4925
ARG COMPAT_LAYER
ARG BOX86_VERSION
ARG BOX64_VERSION
ARG BOX86_DEB_URL
ARG BOX64_DEB_URL
ARG WINE_BRANCH
ARG WINE_ID
ARG WINE_VERSION
ARG WINE_DIST
ARG WINE_TAG
ARG WINE_INSTALL_I386=false
ARG PROTON_VERSION=""
ARG PROTON_INSTALL_I386=false
ARG DEBIAN_FRONTEND=noninteractive

ENV CONTAINER_USER="container" \
    LOGS="/var/log" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    LANGUAGE="en_US.UTF-8" \
    TZ="Etc/UTC" \
    SCRIPTS="/usr/local/bin" \
    TERM="xterm-256color" \
    DISPLAY=":0" \
    STEAMCMD_PATH="/opt/steamcmd" \
    STEAM_SERVER_APPID="" \
    STEAM_PLATFORM_TYPE="linux" \
    STEAM_ID_ALLOW_LIST_PATH="" \
    STEAM_ID_ALLOW_LIST="" \
    STEAM_WORKSHOP_MOD_IDS="" \
    UPDATE_ON_START="true" \
    STEAM_VALIDATE="false" \
    STEAMCMD_RETRIES="5" \
    APP_PID="" \
    APP_EXE="" \
    APP_EXECUTABLE="" \
    APP_PROCESS_NAME="" \
    APP_LOG_NAME="" \
    APP_ARGS="" \
    APP_ARGS_FILE="" \
    APP_FILES="/app" \
    APP_COMMAND="" \
    APP_COMMAND_PREFIX="" \
    ARCH_COMMAND_PREFIX="" \
    COMPAT_COMMAND="" \
    APP_USE_XVFB="false" \
    APP_PID_FILE="/tmp/container/app.pid" \
    SHUTDOWN_TIMEOUT="10" \
    WORLD_FILES="/world" \
    TAIL_PGID="" \
    PACKAGES_BUILD="git" \
    PACKAGES_BASE="tini curl ca-certificates tzdata locales tar gettext-base" \
    PACKAGES_DEV="ncdu btop nano" \
    PACKAGES_AMD64_ONLY="lib32gcc-s1"

ENV WORLD_DIRECTORIES="$WORLD_FILES" \
    HOOK_DIRECTORIES="$SCRIPTS/$CONTAINER_USER/hooks" \
    STEAMCMD_EXEC="$STEAMCMD_PATH/steamcmd.sh" \
    STEAMCMD_PROFILE="$APP_FILES/.steam/profile" \
    STEAMCMD_LOGS="$APP_FILES/.steam/profile/logs" \
    STEAM_LIBRARY="$APP_FILES/.steam/library" \
    WINEPREFIX="$APP_FILES/.compat/wine"

COPY installers /tmp/installers
COPY runtime /tmp/runtime

RUN set -eux; \
    useradd -m -u "$CONTAINER_UID" -d "/home/$CONTAINER_USER" -s /bin/bash "$CONTAINER_USER"; \
    COMMIT_SHORT="$(printf '%s' "$SOURCE_COMMIT" | cut -c1-7)"; \
    COMPAT_LAYER_STR=""; \
    if [ -n "$COMPAT_LAYER" ]; then COMPAT_LAYER_STR="-$COMPAT_LAYER"; fi; \
    printf '# Build: %s-%s-%s%s-%s\n' "$COMMIT_SHORT" "$BUILD_DATE" "$DEBIAN_VERSION_CODENAME" "$COMPAT_LAYER_STR" "$TARGETARCH" >> /etc/environment; \
    printf 'BUILD_ID=%s-%s-%s%s-%s\n' "$COMMIT_SHORT" "$BUILD_DATE" "$DEBIAN_VERSION_CODENAME" "$COMPAT_LAYER_STR" "$TARGETARCH" >> /etc/environment; \
    printf 'DOCKER_UP_REF=%s\n' "$DOCKER_UP_REF" >> /etc/environment; \
    apt-get update; \
    apt-get install -y --no-install-recommends $PACKAGES_BASE $PACKAGES_BUILD; \
    if [[ "$BUILD_VERSION" == *"_dev"* ]]; then apt-get install -y --no-install-recommends $PACKAGES_DEV; fi; \
    git clone --filter=blob:none --no-checkout https://github.com/Teriyakidactyl/docker-up.git "$SCRIPTS/$CONTAINER_USER"; \
    git -C "$SCRIPTS/$CONTAINER_USER" checkout --detach "$DOCKER_UP_REF"; \
    rm -rf "$SCRIPTS/$CONTAINER_USER/.git"; \
    install -m 0755 /tmp/runtime/container/up.sh "$SCRIPTS/$CONTAINER_USER/up.sh"; \
    chown -R root:root "$SCRIPTS/$CONTAINER_USER"; \
    sed -i "/$LANG/s/^# //g" /etc/locale.gen; \
    locale-gen; \
    update-locale LANG="$LANG"; \
    if [ "$TARGETARCH" = "amd64" ]; then \
        apt-get install -y --no-install-recommends $PACKAGES_AMD64_ONLY; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        /tmp/installers/boxes.sh; \
    else \
        echo "Unsupported target architecture: $TARGETARCH" >&2; exit 1; \
    fi; \
    if [ "$COMPAT_LAYER" = "wine" ]; then \
        /tmp/installers/wine.sh; \
    elif [ "$COMPAT_LAYER" = "proton" ]; then \
        /tmp/installers/proton.sh; \
    elif [ -n "$COMPAT_LAYER" ]; then \
        echo "Unsupported compatibility layer: $COMPAT_LAYER" >&2; exit 1; \
    fi; \
    /tmp/installers/steamcmd.sh; \
    printf '%s\n' '# Source image environment' '. /etc/environment' >> "/home/$CONTAINER_USER/.bashrc"; \
    mkdir -p "$STEAMCMD_PATH" "$STEAMCMD_LOGS" "$WORLD_FILES" "$APP_FILES" "$STEAM_LIBRARY" "$LOGS" "/home/$CONTAINER_USER"; \
    chown -R "$CONTAINER_USER:$CONTAINER_USER" "$STEAMCMD_PATH" "$WORLD_FILES" "$APP_FILES" "$LOGS" "/home/$CONTAINER_USER"; \
    chmod 0755 "$STEAMCMD_PATH" "$WORLD_FILES" "$APP_FILES" "$LOGS" "/home/$CONTAINER_USER"; \
    chown -R root:root "$SCRIPTS/$CONTAINER_USER"; \
    find "$SCRIPTS/$CONTAINER_USER" -type d -exec chmod 0755 {} +; \
    find "$SCRIPTS/$CONTAINER_USER" -type f -name '*.sh' -exec chmod 0755 {} +; \
    apt-get autoremove --purge -y $PACKAGES_BUILD; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/installers /tmp/runtime; \
    rm -rf "$LOGS"/*

USER ${CONTAINER_USER}

HEALTHCHECK --interval=1m --timeout=5s --start-period=5m --retries=3 \
    CMD /bin/bash -c 'test -s "$APP_PID_FILE" && kill -0 "$(cat "$APP_PID_FILE")" 2>/dev/null'

ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["/usr/local/bin/container/up.sh"]
