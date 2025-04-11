# Dockerfile for SteamCMD, Wine, Proton, Box86/Box64 depending on platform and compatibility layer
# Provides SteamCMD, Wine, Proton, and Box86/Box64 for specified platform

# ======================================================================================================
# Global ARGs - these will be available to all build stages
# ======================================================================================================
ARG DEBIAN_TAG
ARG TARGETARCH
ARG TARGETPLATFORM
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBIAN_VERSION_CODENAME

# Compatibility layer ARGs
ARG COMPAT_LAYER
ARG DEBUGGER
ARG APP_COMMAND_PREFIX

# ======================================================================================================
# Package ARGs with detailed comments for maintainers
# ======================================================================================================
ARG PACKAGES_AMD64_ONLY="\
    # required for steamcmd, https://packages.debian.org/bookworm/lib32gcc-s1
    lib32gcc-s1"

ARG PACKAGES_ARM_ONLY="\
    # required for Box86 > steamcmd, https://packages.debian.org/bookworm/libc6
    libc6:armhf"
    
ARG PACKAGES_ARM_BUILD="\
    # repo keyring add, https://packages.debian.org/bookworm/gnupg
    gnupg"
    
ARG PACKAGES_BASE_BUILD=""
    
ARG PACKAGES_WINE="\
    # Fake X-Server desktop for Wine https://packages.debian.org/bookworm/xvfb
    ## xauth needed with --no-install-recommends with wine
    xvfb \
    xauth"
    
ARG PACKAGES_BASE="\
    # curl needed for api calls
    curl \
    # curl, steamcmd, https://packages.debian.org/bookworm/ca-certificates
    ca-certificates \
    # timezones, https://packages.debian.org/bookworm/tzdata
    tzdata"
    
ARG PACKAGES_DEV="\
    # disk space analyzer: https://packages.debian.org/trixie/ncdu
    ncdu \
    # top replacement: https://packages.debian.org/trixie/btop
    btop"

# Box version ARGs
ARG BOX86_VERSION
ARG BOX64_VERSION

# Wine ARGs
ARG WINE_BRANCH="staging"
ARG WINE_ID="debian"
ARG WINE_VERSION="9.21"
ARG WINE_DIST=""
ARG WINE_TAG="-1"

# Proton ARG
ARG PROTON_VERSION=""

# ======================================================================================================
# SteamCMD Builder - Always on amd64
# ======================================================================================================
FROM --platform=linux/amd64 debian:${DEBIAN_TAG} AS steamcmd-builder
ARG DEBIAN_FRONTEND
ARG PACKAGES_BASE
ARG PACKAGES_AMD64_ONLY

RUN apt-get update && \
    apt-get install -y --no-install-recommends $PACKAGES_BASE $PACKAGES_AMD64_ONLY && \
    mkdir -p /opt/steamcmd && \
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C /opt/steamcmd && \
    /opt/steamcmd/steamcmd.sh +login anonymous +quit && \
    rm -rf /var/lib/apt/lists/*

# ======================================================================================================
# Box86/Box64 Builder - Only needed for ARM64
# ======================================================================================================
FROM --platform=linux/arm64 debian:${DEBIAN_TAG} AS box-builder
ARG DEBIAN_FRONTEND
ARG PACKAGES_BASE
ARG PACKAGES_ARM_BUILD
ARG BOX86_VERSION
ARG BOX64_VERSION

# Create directories regardless of architecture to avoid COPY errors
RUN mkdir -p /usr/local/bin /usr/local/lib/box64 /usr/local/lib/box86 && \
    # Only run the actual build on ARM64
    if [ "$(uname -m)" = "aarch64" ]; then \
        # Install dependencies
        apt-get update && \
        apt-get install -y --no-install-recommends $PACKAGES_BASE $PACKAGES_ARM_BUILD build-essential cmake git ca-certificates && \
        # Build Box64 for ARM64
        if [ -n "$BOX64_VERSION" ]; then \
            git clone https://github.com/ptitSeb/box64 /tmp/box64 && \
            cd /tmp/box64 && \
            if [ "$BOX64_VERSION" != "latest" ]; then \
                git checkout tags/v${BOX64_VERSION} -b v${BOX64_VERSION}; \
            fi && \
            mkdir build && cd build && \
            # Use ARM64 generic for Oracle Ampere \
            cmake .. -DARM64=1 -DNOGIT=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo && \
            make -j$(nproc) && make install; \
        fi && \
        # Build Box86 for ARM64 (requires multiarch)
        if [ -n "$BOX86_VERSION" ]; then \
            apt-get install -y gcc-arm-linux-gnueabihf && \
            dpkg --add-architecture armhf && \
            apt-get update && \
            apt-get install -y libc6:armhf && \
            git clone https://github.com/ptitSeb/box86 /tmp/box86 && \
            cd /tmp/box86 && \
            if [ "$BOX86_VERSION" != "latest" ]; then \
                git checkout tags/v${BOX86_VERSION} -b v${BOX86_VERSION}; \
            fi && \
            mkdir build && cd build && \
            # Use ADLINK option for Oracle Ampere \
            cmake .. -DADLINK=1 -DNOGIT=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo && \
            make -j$(nproc) && make install; \
        fi && \
        # Clean up
        rm -rf /var/lib/apt/lists/* /tmp/box64 /tmp/box86; \
    else \
        # On non-ARM64 builds, create empty placeholder files
        touch /usr/local/bin/box64 && \
        touch /usr/local/bin/box86 && \
        touch /usr/local/lib/box64/placeholder && \
        touch /usr/local/lib/box86/placeholder; \
    fi

# ======================================================================================================
# Wine Builder - Only if COMPAT_LAYER is wine
# ======================================================================================================
FROM --platform=$TARGETPLATFORM debian:${DEBIAN_TAG} AS wine-builder
ARG DEBIAN_FRONTEND
ARG PACKAGES_BASE
ARG PACKAGES_WINE
ARG WINE_BRANCH
ARG WINE_ID
ARG WINE_VERSION
ARG WINE_DIST
ARG WINE_TAG
ARG COMPAT_LAYER

# Create wine directory regardless of COMPAT_LAYER to avoid COPY errors
RUN mkdir -p /opt/wine-$WINE_BRANCH/bin && \
    # Only process wine if COMPAT_LAYER=wine
    if [ "$COMPAT_LAYER" = "wine" ]; then \
        apt-get update && \
        apt-get install -y --no-install-recommends $PACKAGES_BASE $PACKAGES_WINE && \
        \
        WINEHQ_LINK_AMD64="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-amd64/"; \
        WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"; \
        # (required for wine64 / can work alongside wine_i386 main bin) \
        WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"; \
        WINEHQ_LINK_I386="https://dl.winehq.org/wine-builds/${WINE_ID}/dists/${WINE_DIST}/main/binary-i386/"; \
        WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"; \
        # wine_i386 support files (required for wine_i386 if no wine64 / CONFLICTS WITH wine64 support files) \
        WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"; \    
        \
        # Wine, Windows Emulator, https://packages.debian.org/bookworm/wine, https://wiki.winehq.org/Debian , https://www.winehq.org/news/ \
        # Install wine amd64 in arm64 manually, needed for box64, https://github.com/ptitSeb/box64/blob/main/docs/X64WINE.md \
        ## Wine only translates windows apps, but not arch. Windows apps are almost all x86, so wine:arm doesn't really help. \
        TEMP_DIR="/tmp/wine_debs"; \
        mkdir -p "$TEMP_DIR"; \
        curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_64_MAIN_BIN}"; \
        curl -sL "${WINEHQ_LINK_AMD64}${WINE_64_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}"; \
            # NOTE Skipping wine32 i386 \
            #curl -sL "${WINEHQ_LINK_I386}${WINE_32_MAIN_BIN}" -o "${TEMP_DIR}/${WINE_32_MAIN_BIN}"; \
            #curl -sL "${WINEHQ_LINK_I386}${WINE_32_SUPPORT_BIN}" -o "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}"; \
        dpkg-deb -x "${TEMP_DIR}/${WINE_64_MAIN_BIN}" /; \
        dpkg-deb -x "${TEMP_DIR}/${WINE_64_SUPPORT_BIN}" /; \
            #dpkg-deb -x "${TEMP_DIR}/${WINE_32_MAIN_BIN}" /; \
            #dpkg-deb -x "${TEMP_DIR}/${WINE_32_SUPPORT_BIN}" /; \
        # Cleanup temp directory \
        rm -rf "$TEMP_DIR"; \
        chmod +x $WINE_PATH/wine64 $WINE_PATH/wineboot $WINE_PATH/winecfg $WINE_PATH/wineserver; \
            ## $WINE_PATH/wine \
        rm -rf /var/lib/apt/lists/*; \
    else \
        # Create placeholder files for when wine is not needed
        touch /opt/wine-$WINE_BRANCH/bin/placeholder; \
    fi

# ======================================================================================================
# Proton Builder - Only if COMPAT_LAYER is proton
# ======================================================================================================
FROM --platform=$TARGETPLATFORM debian:${DEBIAN_TAG} AS proton-builder
ARG DEBIAN_FRONTEND
ARG PACKAGES_BASE
ARG PROTON_VERSION
ARG COMPAT_LAYER

# Create proton directory regardless of COMPAT_LAYER to avoid COPY errors
RUN mkdir -p /opt/proton && \
    # Only process proton if COMPAT_LAYER=proton
    if [ "$COMPAT_LAYER" = "proton" ]; then \
        apt-get update && \
        apt-get install -y --no-install-recommends $PACKAGES_BASE curl && \
        # https://github.com/ValveSoftware/Proton \
        # Download Proton from GitHub releases if version is specified \
        if [ -n "$PROTON_VERSION" ]; then \
            PROTON_URL="https://github.com/ValveSoftware/Proton/releases/download/proton-${PROTON_VERSION}/proton-${PROTON_VERSION}.tar.gz" && \
            curl -sL "$PROTON_URL" -o /tmp/proton.tar.gz && \
            tar -xzf /tmp/proton.tar.gz -C /opt/proton --strip-components=1 && \
            rm /tmp/proton.tar.gz; \
        else \
            echo "No Proton version specified" > /opt/proton/README.txt; \
        fi && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        # Create placeholder when proton not needed
        echo "Proton not enabled" > /opt/proton/README.txt; \
    fi

# ======================================================================================================
# Final image - combines components based on architecture and compatibility requirements
# ======================================================================================================
FROM --platform=$TARGETPLATFORM debian:${DEBIAN_TAG} AS final

# Re-declare ARGs for this stage
ARG TARGETARCH
ARG TARGETPLATFORM
ARG DEBIAN_FRONTEND
ARG DEBIAN_VERSION_CODENAME
ARG COMPAT_LAYER
ARG DEBUGGER
ARG APP_COMMAND_PREFIX

# Re-declare package ARGs
ARG PACKAGES_AMD64_ONLY
ARG PACKAGES_ARM_ONLY
ARG PACKAGES_ARM_BUILD
ARG PACKAGES_BASE_BUILD
ARG PACKAGES_WINE
ARG PACKAGES_BASE
ARG PACKAGES_DEV

# Wine ARGs
ARG WINE_BRANCH
ARG WINE_ID
ARG WINE_VERSION
ARG WINE_DIST
ARG WINE_TAG

# Proton ARG
ARG PROTON_VERSION

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
# Box64 Config, Reference: https://github.com/ptitSeb/box64/blob/main/docs/USAGE.md, errors: https://github.com/ptitSeb/box64/issues/1182

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

# Begin installation and setup process

# TODO colored shell prompt
# TODO log rotation @ $LOGS

RUN set -eux; \
    \
    # DEBUG incoming output
    echo "DEBUG: DEBUGGER=${DEBUGGER}"; \
    \
    # Update and install common packages
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PACKAGES_BASE $PACKAGES_BASE_BUILD; \
    \
    # Create and set up $DIRECTORIES permissions
    # links to separate save game files 'stateful' data from application.
    useradd -m -u $PUID -d "/home/$CONTAINER_USER" -s /bin/bash $CONTAINER_USER; \
    mkdir -p $DIRECTORIES; \
    \
    # ARCH Specific Packages -------------------------------------------------------------------------------------
    echo "DEBUG: TARGETARCH=${TARGETARCH}"; \
    if [ "$TARGETARCH" = "arm64" ]; then \
        # Install ARM-specific packages
        apt-get install -y \
            $PACKAGES_ARM_ONLY; \
    elif [ "$TARGETARCH" = "amd64" ]; then \ 
        # AMD64 specific packages
        apt-get install -y \
            $PACKAGES_AMD64_ONLY; \
    fi; \
    \
    # Conditional Wine setup if COMPAT_LAYER is "wine / proton"
    echo "DEBUG: COMPAT_LAYER=${COMPAT_LAYER}"; \
    if [ "$COMPAT_LAYER" = "wine" ]; then \
        apt-get install -y --no-install-recommends \
            $PACKAGES_WINE; \
    fi; \
    \
    # Create steamcmd validation script for runtime
    echo '#!/bin/bash' > /usr/local/bin/validate-steamcmd.sh; \
    echo 'if [ ! -f "$STEAMCMD_PATH/.validated" ]; then' >> /usr/local/bin/validate-steamcmd.sh; \
    echo '    echo "First run - validating SteamCMD installation"' >> /usr/local/bin/validate-steamcmd.sh; \
    echo '    if [ -f /usr/local/bin/box86 ] && [ "$(uname -m)" = "aarch64" ]; then' >> /usr/local/bin/validate-steamcmd.sh; \
    echo '        box86 $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit' >> /usr/local/bin/validate-steamcmd.sh; \
    echo '    else' >> /usr/local/bin/validate-steamcmd.sh; \
    echo '        $STEAMCMD_PATH/steamcmd.sh +login anonymous +quit' >> /usr/local/bin/validate-steamcmd.sh; \
    echo '    fi' >> /usr/local/bin/validate-steamcmd.sh; \
    echo '    touch "$STEAMCMD_PATH/.validated"' >> /usr/local/bin/validate-steamcmd.sh; \
    echo 'fi' >> /usr/local/bin/validate-steamcmd.sh; \
    chmod +x /usr/local/bin/validate-steamcmd.sh; \
    \
    # Final cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get autoremove --purge -y $PACKAGES_BASE_BUILD

# Copy steamcmd from steamcmd-builder (always amd64)
COPY --from=steamcmd-builder /opt/steamcmd /opt/steamcmd

# Copy Box86/Box64 files
COPY --from=box-builder /usr/local/bin/box64 /usr/local/bin/box64
COPY --from=box-builder /usr/local/bin/box86 /usr/local/bin/box86
COPY --from=box-builder /usr/local/lib/box64 /usr/local/lib/box64
COPY --from=box-builder /usr/local/lib/box86 /usr/local/lib/box86

# Make Box86/Box64 executable only on ARM64
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        chmod +x /usr/local/bin/box64 /usr/local/bin/box86; \
    fi

# Copy Wine files
COPY --from=wine-builder /opt/wine-$WINE_BRANCH /opt/wine-$WINE_BRANCH

# Setup Wine symlinks if COMPAT_LAYER=wine
RUN if [ "$COMPAT_LAYER" = "wine" ]; then \
        chmod +x $WINE_PATH/wine64 $WINE_PATH/wineboot $WINE_PATH/winecfg $WINE_PATH/wineserver; \
        ln -sf "$WINE_PATH/wine64" /usr/local/bin/wine64; \
        ln -sf "$WINE_PATH/wine64" /usr/local/bin/wine; \
        ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot; \
        ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg; \
        ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver; \
        # TODO Winesetup; if ! -d $WINEPREFIX, if ARCH = arm, box64 wine64 wineboot -iuf else wine64 wineboot -iuf \
        # NOTE $WINEPREFIX can be large. \
    fi

# Copy Proton files
COPY --from=proton-builder /opt/proton /opt/proton

# Set ownership of all directories
RUN chown -R $CONTAINER_USER:$CONTAINER_USER $DIRECTORIES; \    
    chmod 755 $DIRECTORIES

# Copy scripts and set up user
COPY --chown=$CONTAINER_USER:$CONTAINER_USER scripts $SCRIPTS

USER $CONTAINER_USER

# Set the entrypoint to start the server
# ENTRYPOINT ["/bin/bash", "-c"]
# CMD ["up.sh"]

# Expose application volumes
VOLUME ["$APP_FILES"]
VOLUME ["$WORLD_FILES"]
