ARG DEBIAN_TAG

FROM debian:${DEBIAN_TAG}

# ======================================================================================================
# ECHO BLOCK FORMATTING GUIDELINES
# ======================================================================================================
# This Dockerfile uses two levels of section headers implemented as echo statements:
#
# 1. H1 (Main Section Headers): 150 characters wide with centered text
#    Format:
#    echo "=======================================================================================================================================================================" && \
#    echo "                                                  SECTION NAME                                                                                                       " && \
#    echo "=======================================================================================================================================================================" && \
#
# 2. H2 (Subsection Headers): 150 characters wide with text surrounded by dashes
#    Format:
#    echo "------------------------------------------------------- Subsection Name -----------------------------------------------------------------------" && \
#
# These echo statements create visual separation between logical sections in the build output
# and make debugging and troubleshooting easier by providing clear visual markers in logs.

# ======================================================================================================
# Global ARGs - these will be available to all build stages
# ======================================================================================================
ARG TARGETARCH \
    TARGETPLATFORM \
    DEBIAN_VERSION_CODENAME \
    SOURCE_COMMIT \
    BUILD_DATE \
    BUILD_VERSION \
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
    \
    # Define additional environment variables
    # For storing wine, box64
    APP_COMMAND_PREFIX="" \
    # For holding box86 for steamcmd
    DEBUGGER="" \
    DEBIAN_FRONTEND=noninteractive \
    TERM="xterm-256color" \
    DISPLAY=":0"

ENV WORLD_FILES="/world" \
    WORLD_DIRECTORIES="/home/$CONTAINER_USER/world/States" \
    APP_FILES="/app" \
    \
    # Steamcmd
    STEAMCMD_PATH="/opt/steamcmd" \
    STEAMCMD_PROFILE="/home/$CONTAINER_USER/Steam" \ 
    STEAMCMD_LOGS="/home/$CONTAINER_USER/Steam/logs" \
    STEAM_LIBRARY="/home/$CONTAINER_USER/.local/share/Steam" \
    \
    # Wine
    WINEPREFIX="/home/$CONTAINER_USER/app/Wine" \
    WINEARCH="win64" \
    #  https://wiki.winehq.org/Mono
    #WINE_MONO_VERSION=4.9.4 
    # https://wiki.winehq.org/Debug_Channels
    WINEDEBUG=fixme-all \
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
        btop"

COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} scripts ${SCRIPTS}

RUN set -eux && \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  ARCHITECTURE-SPECIFIC CONFIGURATIONS                                                                                " && \
    echo "=======================================================================================================================================================================" && \
    # Extract first 7 characters of commit hash
    COMMIT_SHORT=$(echo "${SOURCE_COMMIT}" | cut -c1-7) && \
    # Conditionally add COMPAT_LAYER
    COMPAT_LAYER_STR="" && \
    if [ -n "${COMPAT_LAYER}" ]; then \
        COMPAT_LAYER_STR="-${COMPAT_LAYER}"; \
    fi && \
    # Create environment file with header and build fingerprint
    echo "# Build: ${COMMIT_SHORT}-${BUILD_DATE}-${DEBIAN_VERSION_CODENAME}${COMPAT_LAYER_STR}-${TARGETARCH}" >> /etc/environment && \
    echo "BUILD_ID=${COMMIT_SHORT}-${BUILD_DATE}-${DEBIAN_VERSION_CODENAME}${COMPAT_LAYER_STR}-${TARGETARCH}" >> /etc/environment && \
    \
    apt-get update && \
    apt-get install -y --no-install-recommends $PACKAGES_BASE $PACKAGES_BASE_BUILD && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  ARCHITECTURE-SPECIFIC CONFIGURATIONS                                                                                " && \
    echo "=======================================================================================================================================================================" && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        # --- AMD64 Architecture Setup ---
        apt-get install -y --no-install-recommends $PACKAGES_AMD64_ONLY; \
        \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        echo "------------------------------------------------------- ARM64 Architecture Setup -----------------------------------------------------------------------" && \
        # Add section header to environment file
        echo "" >> /etc/environment && \
        echo "# ARM64 Box86/Box64 configuration" >> /etc/environment && \
        \
        # Box86 configuration
        # Creates a Box86 wrapper for x86 apps on ARM64
        echo "DEBUGGER=box86" >> /etc/environment && \
        echo "BOX86_LOG=1" >> /etc/environment && \
        echo "BOX86_TRACE_FILE=${LOGS}/box86.log" >> /etc/environment && \
        \
        # Box64 configuration
        # Reference: https://github.com/ptitSeb/box64/blob/main/docs/USAGE.md
        echo "BOX64_LOG=1" >> /etc/environment && \
        echo "BOX64_DYNAREC_BLEEDING_EDGE=0" >> /etc/environment && \
        echo "BOX64_DYNAREC_BIGBLOCK=0" >> /etc/environment && \
        echo "BOX64_DYNAREC_STRONGMEM=2" >> /etc/environment && \
        echo "BOX64_TRACE_FILE=${LOGS}/box64.log" >> /etc/environment && \
        # echo "BOX64_NOPULSE=1" >> /etc/environment && \
        \
        # Gameserver command prefix
        # For running x86_64 binaries on ARM64 architecture
        if [ -z "$APP_COMMAND_PREFIX" ]; then \
            echo "APP_COMMAND_PREFIX=box64" >> /etc/environment; \
        else \
            echo 'APP_COMMAND_PREFIX="'$APP_COMMAND_PREFIX' box64"' >> /etc/environment; \
        fi && \
        \
        # Add ARM architecture and install packages
        dpkg --add-architecture armhf && \
        apt-get update && \
        apt-get install -y --no-install-recommends $PACKAGES_ARM_ONLY $PACKAGES_ARM_BUILD && \
        \
        # Source the environment file to make variables available in this build stage
        . /etc/environment && \
        \
        # Download and install Box86/Box64
        mkdir -p /usr/local/bin /usr/local/lib/box64 /usr/local/lib/box86 && \
        \
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
    echo "=======================================================================================================================================================================" && \
    echo "                                                  COMPATIBILITY LAYER SETUP                                                                                           " && \
    echo "=======================================================================================================================================================================" && \
    if [ "$COMPAT_LAYER" = "wine" ]; then \
        echo "------------------------------------------------------- Wine Compatibility Layer Setup -----------------------------------------------------------------------" && \
        # Add section header to environment file
        echo "" >> /etc/environment && \
        echo "# Wine compatibility layer configuration" >> /etc/environment && \
        \
        # Wine-specific environment variables
        echo "WINE_PATH=/opt/wine-${WINE_BRANCH}/bin" >> /etc/environment && \
        echo "WINEPREFIX=${WINEPREFIX}" >> /etc/environment && \
        echo "WINEARCH=${WINEARCH}" >> /etc/environment && \
        # https://wiki.winehq.org/Debug_Channels
        echo "WINEDEBUG=fixme-all" >> /etc/environment && \
        \
        # Gameserver command prefix
        # For running Windows executables
        if [ -z "$APP_COMMAND_PREFIX" ]; then \
            echo "APP_COMMAND_PREFIX=wine" >> /etc/environment; \
        else \
            echo 'APP_COMMAND_PREFIX="'$APP_COMMAND_PREFIX' wine"' >> /etc/environment; \
        fi && \
        \
        # Re-source environment after updating the prefix
        . /etc/environment && \
        \
        # Install Wine packages
        apt-get install -y --no-install-recommends $PACKAGES_WINE && \
        mkdir -p $WINE_PATH && \
        \
        # Download and install Wine
        WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/" && \
        WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" && \
        # (required for wine64 / can work alongside wine_i386 main bin)
        WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" && \
        WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/" && \
        WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" && \
        # wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files)
        WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" && \    
        \
        # Wine, Windows Emulator, https://packages.debian.org/bookworm/wine, https://wiki.winehq.org/Debian, https://www.winehq.org/news/
        # Install wine amd64 in arm64 manually, needed for box64, https://github.com/ptitSeb/box64/blob/main/docs/X64WINE.md
        # Wine only translates windows apps, but not arch. Windows apps are almost all x86, so wine:arm doesn't really help.
        TEMP_DIR="/tmp/wine_debs" && \
        mkdir -p "$TEMP_DIR" && \
        curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}" && \
        curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" && \
        # NOTE Skipping wine32 i386
        #curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}" && \
        #curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" && \
        dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" / && \
        dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" / && \
        #dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" / && \
        #dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" / && \
        # Cleanup temp directory
        rm -rf "$TEMP_DIR" && \
        \
        # Setup Wine symlinks
        chmod +x \
                $WINE_PATH/wine \
                $WINE_PATH/wineboot \
                $WINE_PATH/winecfg \
                $WINE_PATH/wineserver && \
        if [ "$TARGETARCH" = "arm64" ]; then \
            echo 'box64 $WINE_PATH/wine "$@"' > /usr/local/bin/wine && \
            chmod +x /usr/local/bin/wine; \
        else \
            ln -sf "$WINE_PATH/wine" /usr/local/bin/wine; \
        fi && \
        ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot && \
        ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg && \
        ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver; \
        \
    elif [ "$COMPAT_LAYER" = "proton" ]; then \
        echo "------------------------------------------------------- Proton Compatibility Layer Setup --------------------------------------------------------------------" && \
        # Add section header to environment file
        echo "" >> /etc/environment && \
        echo "# Proton compatibility layer configuration" >> /etc/environment && \
        \
        mkdir -p /opt/proton && \
        # https://github.com/ValveSoftware/Proton
        # Download Proton from GitHub releases if version is specified
        if [ -n "$PROTON_VERSION" ]; then \
            # Source environment to get the current APP_COMMAND_PREFIX
            . /etc/environment && \
            \
            echo "APP_COMMAND_PREFIX=$APP_COMMAND_PREFIX proton" >> /etc/environment && \
            \
            PROTON_URL="https://github.com/ValveSoftware/Proton/releases/download/proton-${PROTON_VERSION}/proton-${PROTON_VERSION}.tar.gz" && \
            curl -sL "$PROTON_URL" -o /tmp/proton.tar.gz && \
            tar -xzf /tmp/proton.tar.gz -C /opt/proton --strip-components=1 && \
            rm /tmp/proton.tar.gz; \
        else \
            echo "No Proton version specified" > /opt/proton/README.txt; \
        fi; \
    fi && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  STEAMCMD SETUP                                                                                                      " && \
    echo "=======================================================================================================================================================================" && \
    mkdir -p ${STEAMCMD_PATH} && \
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ${STEAMCMD_PATH} && \
    # NOTE due to box86 not running in github docker build, first run should be in container.
    # ${STEAMCMD_PATH}/steamcmd.sh +login anonymous +quit && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  USER AND DIRECTORIES SETUP                                                                                          " && \
    echo "=======================================================================================================================================================================" && \
    useradd -m -u $PUID -d "/home/$CONTAINER_USER" -s /bin/bash $CONTAINER_USER && \
    DIR_LIST="\
        ${STEAMCMD_PATH} \
        ${STEAMCMD_LOGS} \
        ${WORLD_FILES} \
        ${WORLD_DIRECTORIES} \
        ${APP_FILES} \
        ${STEAM_LIBRARY} \
        ${LOGS} \
        ${SCRIPTS}" && \
    mkdir -p $DIR_LIST && \
    chown -R ${CONTAINER_USER}:${CONTAINER_USER} $DIR_LIST && \
    chmod 755 $DIR_LIST && \
    ls -la / && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  FINAL CLEANUP                                                                                                       " && \
    echo "=======================================================================================================================================================================" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  ENVIRONMENT VARIABLES                                                                                               " && \
    echo "=======================================================================================================================================================================" && \
    echo "Contents of /etc/environment:" && \
    cat /etc/environment && \
    \
    echo '# Source environment variables' >> /home/${CONTAINER_USER}/.bashrc && \
    echo '. /etc/environment' >> /home/${CONTAINER_USER}/.bashrc

# Switch to the container user
USER ${CONTAINER_USER}

# TODO insert derivative container examples

# Expose application volumes
# VOLUME ["${APP_FILES}"]
# VOLUME ["${WORLD_FILES}"]

# CMD ["up.sh"]
