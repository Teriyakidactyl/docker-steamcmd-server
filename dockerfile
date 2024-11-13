# Dockerfile for SteamCMD, Wine, Proton, Box86/Box64 depending on platform and compatibility layer
# Provides SteamCMD, Wine, Proton, and Box86/Box64 for specified platform

ARG DEBIAN_TAG
ARG TARGETARCH
ARG TARGETPLATFORM

# Final image setup
FROM --platform=$TARGETPLATFORM debian:$DEBIAN_TAG AS final

ARG TARGETARCH
ARG TARGETPLATFORM

ARG DEBIAN_FRONTEND=noninteractive
ARG DEBIAN_VERSION_CODENAME

ARG COMPAT_LAYER
ARG DEBUGGER
ARG APP_COMMAND_PREFIX

# Wine -----------------------------------------------------------------------------------------------------------
ARG WINE_BRANCH="staging" \
    WINE_ID="debian" \
    WINE_VERSION="9.21" \
    WINE_DIST="" \
    WINE_TAG="-1" 

# Proton -----------------------------------------------------------------------------------------------------
ARG PROTON_VERSION=""

# Packages -------------------------------------------------------------------------------------------------------
ARG  \
    PACKAGES_AMD64_ONLY="\
        # required for steamcmd, https://packages.debian.org/bookworm/lib32gcc-s1
        lib32gcc-s1" \ 
         \
    PACKAGES_ARM_ONLY="\
        # required for Box86 > steamcmd, https://packages.debian.org/bookworm/libc6
        libc6:armhf" \
        \
    PACKAGES_ARM_BUILD="\
        # repo keyring add, https://packages.debian.org/bookworm/gnupg
        gnupg" \
        \
    PACKAGES_BASE_BUILD="" \
        \
    PACKAGES_WINE="\
        # Fake X-Server desktop for Wine https://packages.debian.org/bookworm/xvfb
        ## xauth needed with --no-install-recommends with wine
        xvfb \
        xauth" \
        \
    PACKAGES_BASE="\
        # curl needed for api calls
        curl \
        # curl, steamcmd, https://packages.debian.org/bookworm/ca-certificates
        ca-certificates \
        # timezones, https://packages.debian.org/bookworm/tzdata
        tzdata" \
        \
    PACKAGES_DEV="\
        # disk space analyzer: https://packages.debian.org/trixie/ncdu
        ncdu \
        # top replacement: https://packages.debian.org/trixie/btop
        btop"

# Define environment variables
    # NOTE: In Docker 1.10 and higher, only RUN, COPY, and ADD instructions create layers.

# Base -----------------------------------------------------------------------------------------------------------
ENV CONTAINER_USER="container"
ENV PUID="1000"
ENV TERM="xterm-256color"
ENV DISPLAY=":0"
ENV DEBUGGER="${DEBUGGER}"
ENV LOGS="/var/log"
ENV SCRIPTS="/usr/local/bin"

# World ----------------------------------------------------------------------------------------------------------
ENV WORLD_FILES="/world"
ENV WORLD_DIRECTORIES="$WORLD_FILES/States"

# App ------------------------------------------------------------------------------------------------------------
ENV APP_FILES="/app"
ENV APP_COMMAND_PREFIX="${APP_COMMAND_PREFIX}"
    # NOTE Examples:
    # APP_NAME="game_server" \
    # APP_EXE="$APP_FILES/game_server_executable" \
    # APP_LOGS="/var/log/$APP_NAME" \

# Steam ----------------------------------------------------------------------------------------------------------
ENV STEAMCMD_PATH="/opt/steamcmd"
ENV STEAMCMD_PROFILE="/home/$CONTAINER_USER/Steam"
ENV STEAMCMD_LOGS="$STEAMCMD_PROFILE/logs"
ENV HOME=$STEAMCMD_PATH
    # NOTE: https://github.com/ValveSoftware/steam-for-linux/issues/10979
    ## ^ Bugfix RE: ERROR! Failed to install app (Missing file permissions)
ENV STEAM_LIBRARY="$APP_FILES/Steam"
    # NOTE Examples:
    # STEAM_ALLOW_LIST_PATH="" \
    # STEAM_SERVER_APPID="" \
    # STEAM_CLIENT_APPID="" \

# Wine -----------------------------------------------------------------------------------------------------------
ENV WINE_PATH="/opt/wine-$WINE_BRANCH/bin"
ENV WINEPREFIX="/app/Wine"
ENV WINEARCH="win64"
ENV WINEDEBUG="fixme-all"

# Box86 ----------------------------------------------------------------------------------------------------------
# https://github.com/ptitSeb/box86/blob/master/docs/USAGE.md
ENV BOX86_LOG=1
ENV BOX86_TRACE_FILE="$LOGS/box86.log"

# Box64 ----------------------------------------------------------------------------------------------------------
# Box64 + Wine: https://github.com/ptitSeb/box64/blob/main/docs/X64WINE.md
## https://forum.armbian.com/topic/19526-how-to-install-box86-box64-wine32-wine64-winetricks-on-arm64/
# https://community.fydeos.io/t/topic/26128
# Box64 Config, Refference: https://github.com/ptitSeb/box64/blob/main/docs/USAGE.md ,errors: https://github.com/ptitSeb/box64/issues/1182
ENV BOX64_LOG=1
ENV BOX64_DYNAREC_BLEEDING_EDGE=0
ENV BOX64_DYNAREC_BIGBLOCK=0
ENV BOX64_DYNAREC_STRONGMEM=2
ENV BOX64_TRACE_FILE="$LOGS/box64.log"

ENV DIRECTORIES="\
        $WINE_PATH \
        $WORLD_FILES \
        $WORLD_DIRECTORIES \
        $APP_FILES \
        $STEAM_LIBRARY \
        $STEAMCMD_PATH \
        $STEAMCMD_LOGS \
        $LOGS \
        $SCRIPTS"

# Begin installation and setup process in a single RUN statement
RUN set -eux; \
    \
    # DEBUG incoming output
    echo "DEBUG: DEBUGGER=${DEBUGGER}"; \
    \
    # Update and install common BASE_DEPENDENCIES
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PACKAGES_BASE $PACKAGES_BASE_BUILD; \
    \
    # Create and set up $DIRECTORIES permissions
    # links to seperate save game files 'stateful' data from application.
    useradd -m -u $PUID -d "/home/$CONTAINER_USER" -s /bin/bash $CONTAINER_USER; \
    mkdir -p $DIRECTORIES; \
    \
    # Conditional Wine setup if COMPAT_LAYER is "wine / proton"
    echo "DEBUG: COMAT_LAYER=${COMPAT_LAYER}"; \
    if [ "$COMPAT_LAYER" = "wine" ]; then \
        apt-get install -y --no-install-recommends \
            $PACKAGES_WINE; \
        \
        WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/"; \
        WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"; \
        # (required for wine64 / can work alongside wine_i386 main bin) 
        WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"; \
        WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/"; \
        WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"; \
        # wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files) 
        WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"; \    
        \
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
        # TODO Cleanup $TEMP_DIR
        chmod +x $WINE_PATH/wine64 $WINE_PATH/wineboot $WINE_PATH/winecfg $WINE_PATH/wineserver; \
            ## $WINE_PATH/wine
        # Create symlinks for Wine binaries
        ln -sf "$WINE_PATH/wine64" /usr/local/bin/wine64; \
        ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot; \
        ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg; \
        ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver; \
        # TODO Winesetup; if ! -d $WINEPREFIX, if ARCH = arm, box64 wine64 wineboot -iuf else wine64 wineboot -iuf
        # NOTE $WINEPREFIX can be large.  
    # Conditional Proton setup if COMPAT_LAYER is "proton"
    elif [ "$COMPAT_LAYER" = "proton" ]; then \
        # https://github.com/ValveSoftware/Proton
        # Proton installation (Placeholder for actual Proton installation logic)
        echo "Proton installation is not yet implemented in this Dockerfile."; \
    fi; \
    \
    # ARCH Specific Packages -------------------------------------------------------------------------------------
    echo "DEBUG: TARGETARCH=${TARGETARCH}"; \
    if echo "$TARGETARCH" | grep -q "arm"; then \
        # Add ARM architecture and update
        dpkg --add-architecture armhf; \
        apt-get update; \
        \
        # Install ARM-specific packages
        apt-get install -y \
            $PACKAGES_ARM_ONLY $PACKAGES_ARM_BUILD; \
        \
        # Add and configure Box86: https://github.com/ryanfortner/box86-debs, alternate: https://itai-nelken.github.io/weekly-box86-debs/
        # commit list: https://github.com/ryanfortner/box86-debs/commits/master
        curl -fsSL https://ryanfortner.github.io/box86-debs/box86.list -o /etc/apt/sources.list.d/box86.list; \
        curl -fsSL https://ryanfortner.github.io/box86-debs/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box86-debs-archive-keyring.gpg; \
        \
        # Add and configure Box64: https://github.com/ryanfortner/box64-debs
        # commit list: https://github.com/ryanfortner/box64-debs/commits/master
        curl -fsSL https://ryanfortner.github.io/box64-debs/box64.list -o /etc/apt/sources.list.d/box64.list; \
        curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg; \
        \
        # Update and install Box86/Box64
        apt-get update; \
        apt-get install -y --no-install-recommends \
            box64 box86-generic-arm; \
        # Debug
        # box86 --vesion; \
        # box64 --version; \
        \
        # Clean up
        apt-get autoremove --purge -y $PACKAGES_ARM_BUILD; \
    else \ 
        # AMD64 specific packages
        apt-get install -y \
            $PACKAGES_AMD64_ONLY; \
    fi; \
    \
    # Install SteamCMD -------------------------------------------------------------------------------------------
    # NOTE steamcmd.sh only runs on amd64. arm64 requires box86. Box86 won't run inside buildx (github-actions)
        curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C $STEAMCMD_PATH; \
    # FIXME remove || true when done testing.
    $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit || true; \
    \
    # Create the container user
    chown -R $CONTAINER_USER:$CONTAINER_USER $DIRECTORIES; \    
    chmod 755 $DIRECTORIES; \ 
    \
    # Final cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get autoremove --purge -y $PACKAGES_BASE_BUILD;

COPY --chown=$CONTAINER_USER:$CONTAINER_USER scripts $SCRIPTS

USER $CONTAINER_USER

# Set the entrypoint to start the server
# ENTRYPOINT ["/bin/bash", "-c"]
# CMD ["up.sh"]

# Expose application volumes
VOLUME ["$APP_FILES"]
VOLUME ["$WORLD_FILES"]
