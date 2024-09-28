# Docker debian:bookworm-slim that provides steamcmd, wine and box64/86 as needed.
# creates user called container with UID 1000

# Stage 1: SteamCMD Install ---------------------------------------------------------------------------------------------------
FROM --platform=linux/amd64 debian:bookworm-slim AS opt-steamcmd

ARG DEBIAN_FRONTEND=noninteractive

ENV STEAMCMD_PATH="/opt/steamcmd"

RUN apt-get update; \
    apt-get install -y curl lib32gcc-s1; \
    mkdir -p $STEAMCMD_PATH; \
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C $STEAMCMD_PATH; \
    $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit; 

# TODO Stage 2: Proton...

# Stage 2: Wine Install -------------------------------------------------------------------------------------------------------
FROM --platform=linux/amd64 debian:bookworm-slim AS opt-wine

ARG DEBIAN_FRONTEND=noninteractive

# Manual amd64 wine for Box64, https://dl.winehq.org/wine-builds > https://dl.winehq.org/wine-builds/debian/dists/trixie/main/binary-amd64/
## WINE_PATH from winehq debs
ENV WINE_BRANCH="staging" \
    WINE_PATH="/opt/wine-staging/bin" \
    WINE_VERSION="9.13" \
    WINE_ID="debian" \
    WINE_DIST="bookworm" \
    WINE_TAG="-1" 

# Set Wine download links for amd64
ENV WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/" \
    WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" \
    # (required for wine64 / can work alongside wine_i386 main bin) 
    WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb" \
    WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/" \
    WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb" \
    # wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files) 
    WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"    

RUN \   
    # Wine, Windows Emulator, https://packages.debian.org/bookworm/wine, https://wiki.winehq.org/Debian , https://www.winehq.org/news/
    # Install wine amd64 in arm64 manually, needed for box64, https://github.com/ptitSeb/box64/blob/main/docs/X64WINE.md
    ## Wine only translates windows apps, but not arch. Windows apps are almost all x86, so wine:arm doesn't really help.
    TEMP_DIR="/tmp/wine_debs"; \
    mkdir -p "$TEMP_DIR"; \
    curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}"; \
    curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}"; \
        # NOTE Skipping wine32 i386 
        #curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}"; \
        #curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}"; \
    dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" /; \
    dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" /; \
        #dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" /; \
        #dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" /; \
    chmod +x $WINE_PATH/wine64 $WINE_PATH/wineboot $WINE_PATH/winecfg $WINE_PATH/wineserver;
        ## $WINE_PATH/wine

# Stage 3: Final ---------------------------------------------------------------------------------------------------------------
# Refference: https://conanexiles.fandom.com/wiki/Dedicated_Server_Setup:_Linux_and_Wine
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive \
    TARGETARCH \
    WINE \
    PACKAGES_AMD64_ONLY=" \
        # required for steamcmd, https://packages.debian.org/bookworm/lib32gcc-s1
        lib32gcc-s1" \ 
         \
    PACKAGES_ARM_ONLY=" \
        # required for Box86 > steamcmd, https://packages.debian.org/bookworm/libc6
        libc6:armhf" \
        \
    PACKAGES_ARM_BUILD=" \
        # repo keyring add, https://packages.debian.org/bookworm/gnupg
        gnupg" \
        \
    PACKAGES_BASE_BUILD="" \
        \
    PACKAGES_BASE=" \
        # Fake X-Server desktop for Wine https://packages.debian.org/bookworm/xvfb
        ## xauth needed with --no-install-recommends with wine
        xvfb \
        xauth \
        # curl needed for api calls
        curl \
        # curl, steamcmd, https://packages.debian.org/bookworm/ca-certificates
        ca-certificates \
        # timezones, https://packages.debian.org/bookworm/tzdata
        tzdata" \
        \
    PACKAGES_DEV=" \
        # disk space analyzer: https://packages.debian.org/trixie/ncdu
        ncdu \
        # top replacement: https://packages.debian.org/trixie/btop
        btop"
    
ENV \
    # Primary Variables
    APP_NAME \
    APP_EXE \
    APP_FILES="/app" \
    STEAM_ALLOW_LIST_PATH \
    WORLD_FILES="/world" \
    STEAMCMD_PATH="/opt/steamcmd" \
    WINE_PATH="/opt/wine-staging/bin" \
    SCRIPTS="/usr/local/bin" \
    LOGS="/var/log" \
    TERM="xterm-256color" \
    DISPLAY=":0" \
    CONTAINER_USER="container" \
    PUID="1000" \
    \
    # Log settings
    # TODO move to file, get more comprehensive.  
    LOG_FILTER_SKIP=""

ENV \
    # Derivative Variables
    \
    # Steamcmd
    STEAMCMD_PROFILE="/home/$CONTAINER_USER/Steam" \
    STEAM_LIBRARY="$APP_FILES/Steam" \
    \
    APP_LOGS="$LOGS/$APP_NAME" \
    WINEPREFIX="/app/Wine"
        	
ENV \   
    STEAMCMD_LOGS="$STEAMCMD_PROFILE/logs" \
    DIRECTORIES=" \ 
        $WINE_PATH \
        $WORLD_FILES \
        $WORLD_DIRECTORIES \
        $APP_FILES \
        $APP_LOGS \
        $LOGS \
        $STEAM_LIBRARY \
        $STEAMCMD_PATH \
        $STEAMCMD_LOGS \
        $SCRIPTS"

    # STEAM_SERVER_APPID
    # STEAM_CLIENT_APPID
    # STEAM_ALLOW_LIST_PATH

    # WINEARCH="win64"
    # WINEDEBUG=fixme-all                  # https://wiki.winehq.org/Debug_Channels
    # WINEPREFIX

# Copy SteamCMD
COPY --from=opt-steamcmd $STEAMCMD_PATH $STEAMCMD_PATH

# TODO if Proton copy Proton ...
# TODO if WINE copy Wine
COPY --from=opt-wine $STEAMCMD_PATH $STEAMCMD_PATH

# Copy scripts after changing to CONTAINER_USER
COPY --chown=$CONTAINER_USER:$CONTAINER_USER scripts $SCRIPTS

# Copy steamcmd user profile (8mb)
COPY --from=opt-steamcmd --chown=$CONTAINER_USER:$CONTAINER_USER /root/Steam $STEAMCMD_PROFILE 

# Update package lists and install required packages
RUN set -eux; \
    \
    # Update and install common BASE_DEPENDENCIES
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PACKAGES_BASE $PACKAGES_BASE_BUILD $PACKAGES_DEV; \
    \
    # Create and set up $DIRECTORIES permissions
    # links to seperate save game files 'stateful' data from application.
    useradd -m -u $PUID -d "/home/$CONTAINER_USER" -s /bin/bash $CONTAINER_USER; \
    mkdir -p $DIRECTORIES; \
    \
    if echo "$WINE" | grep -q "true"; then \
        # Create symlinks for wine
        # NOTE Skipping wine32 i386
            # ln -sf "$WINE_PATH/wine" /usr/local/bin/wine; \
        ln -sf "$WINE_PATH/wine64" /usr/local/bin/wine64; \
        ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot; \
        ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg; \
        ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver; \   
    fi; \ 
    \
    # TODO touch and link steamcmd log to /var/log
    chown -R $CONTAINER_USER:$CONTAINER_USER $DIRECTORIES; \    
    chmod 755 $DIRECTORIES; \  
    \
    # Architecture-specific setup for ARM
    if echo "$TARGETARCH" | grep -q "arm"; then \
        # Add ARM architecture and update
        dpkg --add-architecture armhf; \
        apt-get update; \
        \
        # Install ARM-specific packages
        apt-get install -y --no-install-recommends \
            $PACKAGES_ARM_ONLY $PACKAGES_ARM_BUILD; \
        \
        # Add and configure Box86: https://box86.debian.ryanfortner.dev/
        curl -fsSL https://itai-nelken.github.io/weekly-box86-debs/debian/box86.list -o /etc/apt/sources.list.d/box86.list; \
        curl -fsSL https://itai-nelken.github.io/weekly-box86-debs/debian/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box86-debs-archive-keyring.gpg; \
        \
        # Add and configure Box64: https://box64.debian.ryanfortner.dev/
        curl -fsSL https://ryanfortner.github.io/box64-debs/box64.list -o /etc/apt/sources.list.d/box64.list; \
        curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg; \
        \
        # Update and install Box86/Box64
        apt-get update; \
        apt-get install -y --no-install-recommends \
            box64 box86; \ 
        \
        # TODO touch and link box64, box86 logs to /var/log
        # Clean up
        apt-get autoremove --purge -y $PACKAGES_ARM_BUILD; \
    else \ 
        # AMD64 specific packages
        apt-get install -y --no-install-recommends \
            $PACKAGES_AMD64_ONLY; \
    fi; \
    # Final cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get autoremove --purge -y $PACKAGES_BASE_BUILD

# Change to non-root CONTAINER_USER
USER $CONTAINER_USER

# https://docs.docker.com/reference/dockerfile/#volume
VOLUME ["$APP_FILES"]
VOLUME ["$WORLD_FILES"]

HEALTHCHECK --interval=1m --timeout=3s CMD pidof $APP_EXE || exit 1

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["up.sh"]
