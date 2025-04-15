ARG DEBIAN_TAG

FROM debian:${DEBIAN_TAG}

# ======================================================================================================
# Global ARGs - these will be available to all build stages
# ======================================================================================================
ARG TARGETARCH \
    TARGETPLATFORM \
    DEBIAN_VERSION_CODENAME \
    \
    # Compatibility layer ARGs
    COMPAT_LAYER \
    \
    # Box version ARGs
    BOX86_VERSION \
    BOX64_VERSION \
    BOX86_DEB_URL \
    BOX64_DEB_URL \
    \
    # Wine ARGs
    WINE_BRANCH \
    WINE_ID \
    WINE_VERSION \
    WINE_DIST \
    WINE_TAG \
    \
    # Proton ARG
    PROTON_VERSION=""

# ======================================================================================================
# Define ENV variables for paths and packages
# ======================================================================================================
ENV CONTAINER_USER="container" \
    PUID="1000" \
    LOGS="/var/log" \
    SCRIPTS="/usr/local/bin" \
    WORLD_FILES="/world" \
    WORLD_DIRECTORIES="/world/States" \
    APP_FILES="/app" \
    \
    # Steamcmd
    STEAMCMD_PATH="/opt/steamcmd" \
    STEAMCMD_PROFILE="/home/container/Steam" \
    STEAMCMD_LOGS="/home/container/Steam/logs" \
    STEAM_LIBRARY="/app/Steam" \
    \
    # Wine
    WINEPREFIX="/app/Wine" \
    WINEARCH="win64" \
    \
    # Package definitions with detailed comments for maintainers
    PACKAGES_AMD64_ONLY="\
        # required for steamcmd
        lib32gcc-s1" \
        \
    PACKAGES_ARM_ONLY="\
        # required for Box86 > steamcmd
        libc6:armhf" \
        \
    PACKAGES_ARM_BUILD="" \
    PACKAGES_BASE_BUILD="" \
    PACKAGES_WINE="\
        # Fake X-Server desktop for Wine
        # xauth needed with --no-install-recommends with wine
        xvfb \
        xauth" \
        \
    PACKAGES_BASE="\
        # curl needed for api calls
        curl \
        # curl, steamcmd
        ca-certificates \
        # timezones
        tzdata \
        # Required for extracting archives
        tar" \
        \
    PACKAGES_DEV="\
        # disk space analyzer
        ncdu \
        # top replacement
        btop" \
    \
    # Define additional environment variables
    DEBUGGER="" \
    DEBIAN_FRONTEND=noninteractive \
    TERM="xterm-256color" \
    DISPLAY=":0" \
    APP_COMMAND_PREFIX="${APP_COMMAND_PREFIX}" \
    HOME="${STEAMCMD_PATH}"


COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} scripts ${SCRIPTS}

# ======================================================================================================
# Combined RUN statement - integrates all previous build stages
# ======================================================================================================
RUN set -eux && \
    # ======================================================================================================
    # Setup base directories and install common packages
    # ======================================================================================================
    apt-get update && \
    apt-get install -y --no-install-recommends $PACKAGES_BASE $PACKAGES_BASE_BUILD && \
    \
    # ======================================================================================================
    # Architecture-specific packages and configurations
    # ======================================================================================================
    if [ "$TARGETARCH" = "amd64" ]; then \
        # ======================================================================================================
        # AMD64 setup
        # ======================================================================================================
        apt-get install -y --no-install-recommends $PACKAGES_AMD64_ONLY; \
        \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        # ======================================================================================================
        # ARM64 setup with Box86/Box64
        # ======================================================================================================
        # Box86/Box64 environment variables
        \
        # Box86 configuration
        export DEBUGGER="box86" && \
        export BOX86_LOG=1 && \
        export BOX86_TRACE_FILE="${LOGS}/box86.log" && \
        \
        # Box64 configuration
        export BOX64_LOG=1 && \
        export BOX64_DYNAREC_BLEEDING_EDGE=0 && \
        export BOX64_DYNAREC_BIGBLOCK=0 && \
        export BOX64_DYNAREC_STRONGMEM=2 && \
        export BOX64_TRACE_FILE="${LOGS}/box64.log" && \
        \
        # Add ARM architecture and install ARM-specific packages
        dpkg --add-architecture armhf && \
        apt-get update && \
        apt-get install -y --no-install-recommends $PACKAGES_ARM_ONLY $PACKAGES_ARM_BUILD && \
        \
        # Download and install precompiled Box86/Box64 based on version
        mkdir -p /usr/local/bin /usr/local/lib/box64 /usr/local/lib/box86 && \
        \
        # Download and install specific Box86/Box64 .deb packages
        if [ -n "$BOX86_DEB_URL" ]; then \
            echo "Downloading Box86 from: $BOX86_DEB_URL" && \
            curl -L "$BOX86_DEB_URL" -o /tmp/box86.deb && \
            dpkg -i /tmp/box86.deb || apt-get -f install -y && \
            rm -f /tmp/box86.deb; \
        fi && \
        \
        if [ -n "$BOX64_DEB_URL" ]; then \
            echo "Downloading Box64 from: $BOX64_DEB_URL" && \
            curl -L "$BOX64_DEB_URL" -o /tmp/box64.deb && \
            dpkg -i /tmp/box64.deb || apt-get -f install -y && \
            rm -f /tmp/box64.deb; \
        fi; \
    fi && \
    \
    # ======================================================================================================
    # Compatibility layer setup
    # ======================================================================================================
    if [ "$COMPAT_LAYER" = "wine" ]; then \
        # ======================================================================================================
        # Wine compatibility layer
        # ======================================================================================================
        # Wine-specific environment variables
        export WINE_PATH="/opt/wine-${WINE_BRANCH}/bin" && \
        export WINEPREFIX="${WINEPREFIX}" && \
        export WINEARCH="${WINEARCH}" && \
        export WINEDEBUG="fixme-all" && \
        \
        # Install Wine packages
        apt-get install -y --no-install-recommends $PACKAGES_WINE && \
        mkdir -p $WINE_PATH && \
        \
        # Download and install Wine
        WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/" && \
        WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" && \
        # (required for wine64 / can work alongside wine_i386 main bin) \
        WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" && \
        WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/" && \
        WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" && \
        # wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files) \
        WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" && \    
        \
        # Wine, Windows Emulator, https://packages.debian.org/bookworm/wine, https://wiki.winehq.org/Debian , https://www.winehq.org/news/ \
        # Install wine amd64 in arm64 manually, needed for box64, https://github.com/ptitSeb/box64/blob/main/docs/X64WINE.md \
        ## Wine only translates windows apps, but not arch. Windows apps are almost all x86, so wine:arm doesn't really help. \
        TEMP_DIR="/tmp/wine_debs" && \
        mkdir -p "$TEMP_DIR" && \
        curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}" && \
        curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" && \
            # NOTE Skipping wine32 i386 \
            #curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}" && \
            #curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" && \
        dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" / && \
        dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" / && \
            #dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" / && \
            #dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" / && \
        # Cleanup temp directory \
        rm -rf "$TEMP_DIR" && \
        \
        # Setup Wine symlinks \
        chmod +x \
                $WINE_PATH/wine \
                $WINE_PATH/wineboot \
                $WINE_PATH/winecfg \
                $WINE_PATH/wineserver && \
        ln -sf "$WINE_PATH/wine" /usr/local/bin/wine && \
        ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot && \
        ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg && \
        ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver; \
        \
    elif [ "$COMPAT_LAYER" = "proton" ]; then \
        # ======================================================================================================
        # Proton compatibility layer
        # ======================================================================================================
        mkdir -p /opt/proton && \
        # https://github.com/ValveSoftware/Proton \
        # Download Proton from GitHub releases if version is specified \
        if [ -n "$PROTON_VERSION" ]; then \
            PROTON_URL="https://github.com/ValveSoftware/Proton/releases/download/proton-${PROTON_VERSION}/proton-${PROTON_VERSION}.tar.gz" && \
            curl -sL "$PROTON_URL" -o /tmp/proton.tar.gz && \
            tar -xzf /tmp/proton.tar.gz -C /opt/proton --strip-components=1 && \
            rm /tmp/proton.tar.gz; \
        else \
            echo "No Proton version specified" > /opt/proton/README.txt; \
        fi; \
    fi && \
    \
    # ======================================================================================================
    # SteamCMD setup
    # ======================================================================================================
    mkdir -p ${STEAMCMD_PATH} && \
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ${STEAMCMD_PATH} && \
    # NOTE due to box86 not running in github docker build, first run should be in container.
    # echo "DEBUG: DEBUGGER=$DEBUGGER, ARCH:$(uname -m)" && \
    # ${STEAMCMD_PATH}/steamcmd.sh +login anonymous +quit && \
    \
    # ======================================================================================================
    # Create user and directories
    # ======================================================================================================
    useradd -m -u $PUID -d "/home/$CONTAINER_USER" -s /bin/bash $CONTAINER_USER && \
    DIR_LIST="${STEAMCMD_PATH} ${STEAMCMD_LOGS} ${WORLD_FILES} ${WORLD_DIRECTORIES} ${APP_FILES} ${STEAM_LIBRARY} ${LOGS} ${SCRIPTS}" && \
    mkdir -p $DIR_LIST && \
    chown -R ${CONTAINER_USER}:${CONTAINER_USER} $DIR_LIST && \
    chmod 755 $DIR_LIST && \
    ls -la / && \
    \
    # ======================================================================================================
    # Final cleanup
    # ======================================================================================================
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch to the container user
USER ${CONTAINER_USER}

# Expose application volumes
VOLUME ["${APP_FILES}"]
VOLUME ["${WORLD_FILES}"]

# CMD ["up.sh"]