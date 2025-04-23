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
    WINE_INSTALL_I386 \
    \
    # Proton ARG
    PROTON_VERSION="" \
    PROTON_INSTALL_I386

# ======================================================================================================
# Define ENV variables for paths and packages
# ======================================================================================================
ENV CONTAINER_USER="container" \
    PUID="1000" \
    LOGS="/var/log" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    LANGUAGE="en_US.UTF-8" \
    TZ="America/Vancouver" \
    SCRIPTS="/usr/local/bin" \
    DEBIAN_FRONTEND=noninteractive \
    TERM="xterm-256color" \
    DISPLAY=":0" \
    \
    # Steamcmd
    STEAMCMD_PATH="/opt/steamcmd" \
    STEAM_SERVER_APPID="" \
    STEAM_PLATFORM_TYPE="linux" \
    \
    WORLD_FILES="/world" \
    APP_FILES="/app" \
    # APP_COMMAND: This is a placeholder, derivative containers should replace it
    APP_COMMAND="" \
    \
    PACKAGES_BUILD=" \
    # Needed to pull docker-logging
    git" \
    \
    # Package definitions with minimal base packages
    PACKAGES_BASE="\
        # Init system
        tini \
        # curl needed for api calls
        curl \
        # curl, steamcmd
        ca-certificates \
        # timezones
        tzdata \
        # localization stops some steamcmd warnings.
        locales \
        # Required for extracting archives
        tar" \
        \
    PACKAGES_DEV="\
        # disk space analyzer
        ncdu \
        # top replacement
        btop \
        # Easy editor
        nano" \
    \
    # Package definitions with detailed comments for maintainers
    PACKAGES_AMD64_ONLY="\
        # required for steamcmd
        lib32gcc-s1"

# Secondary ENV
ENV WORLD_DIRECTORIES="/home/$CONTAINER_USER/world/States" \
    \
    # Steamcmd
    STEAMCMD_EXEC="$STEAMCMD_PATH/steamcmd.sh" \
    STEAMCMD_PROFILE="/home/$CONTAINER_USER/Steam" \ 
    STEAMCMD_LOGS="/home/$CONTAINER_USER/Steam/logs" \
    STEAM_LIBRARY="/home/$CONTAINER_USER/.local/share/Steam" \
    \
    # Wine
    WINEPREFIX="/home/$CONTAINER_USER/app/Wine"
    # The WINEARCH value will be determined by the wine installer script based on version

# Copy installer scripts
COPY installers /tmp/installers

RUN set -eux && \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  USER SETUP                                                                                                          " && \
    echo "=======================================================================================================================================================================" && \
    useradd -m -u $PUID -d "/home/$CONTAINER_USER" -s /bin/bash $CONTAINER_USER && \
    # BUILD TAGS
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
    apt-get install -y --no-install-recommends $PACKAGES_BASE $PACKAGES_BUILD && \
    if echo "$BUILD_VERSION" | grep -q "_dev"; then \
        echo "Installing development packages..." && \
        apt-get install -y --no-install-recommends $PACKAGES_DEV; \
    fi && \
    \
    # Install docker-up base scripts
    git clone https://github.com/Teriyakidactyl/docker-up.git $SCRIPTS/container && \
    rm -rf "$SCRIPTS/container/.git" && \
    \
    echo "------------------------------------------------------- Localization ------------------------------------------------------------------------------------------" && \
    sed -i "/$LANG/s/^# //g" /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=$LANG && \
    locale && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  ARCHITECTURE-SPECIFIC CONFIGURATIONS                                                                                " && \
    echo "=======================================================================================================================================================================" && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        echo "------------------------------------------------------- AMD64 Architecture Setup -----------------------------------------------------------------------" && \
        apt-get install -y --no-install-recommends $PACKAGES_AMD64_ONLY; \
        \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        echo "------------------------------------------------------- ARM64 Architecture Setup -----------------------------------------------------------------------" && \
        /tmp/installers/boxes.sh;\
    fi && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  COMPATIBILITY LAYER SETUP                                                                                           " && \
    echo "=======================================================================================================================================================================" && \
    if [ "$COMPAT_LAYER" = "wine" ]; then \
        /tmp/installers/wine.sh; \
    elif [ "$COMPAT_LAYER" = "proton" ]; then \ 
        /tmp/installers/proton.sh; \
    fi && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  STEAMCMD SETUP                                                                                                      " && \
    echo "=======================================================================================================================================================================" && \
    \
    /tmp/installers/steamcmd.sh && \
    \
    # Clean up installers after all installations are complete    
    rm -rf /tmp/installers && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  ENVIRONMENT VARIABLES                                                                                               " && \
    echo "=======================================================================================================================================================================" && \
    echo "Contents of /etc/environment:" && \
    cat /etc/environment && \
    \
    echo '# Source environment variables' >> /home/${CONTAINER_USER}/.bashrc && \
    echo '. /etc/environment' >> /home/${CONTAINER_USER}/.bashrc && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  Final Permission                                                                                                    " && \
    echo "=======================================================================================================================================================================" && \
    DIR_LIST="\
        ${STEAMCMD_PATH} \
        ${STEAMCMD_LOGS} \
        ${WORLD_FILES} \
        ${WORLD_DIRECTORIES} \
        ${APP_FILES} \
        ${STEAM_LIBRARY} \
        ${LOGS} \
        ${SCRIPTS}\
        /home/${CONTAINER_USER}" && \
    mkdir -p $DIR_LIST && \
    chown -R ${CONTAINER_USER}:${CONTAINER_USER} $DIR_LIST && \
    chmod 755 $DIR_LIST && \
    ls -la / && \
    find ~ -type d -exec ls -ld {} \; && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  FINAL CLEANUP                                                                                                       " && \
    echo "=======================================================================================================================================================================" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get autoremove --purge -y $PACKAGES_BUILD

USER ${CONTAINER_USER}

COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} scripts ${SCRIPTS}

HEALTHCHECK --interval=1m --timeout=3s CMD pidof $APP_EXE || exit 1

# Expose application volumes
# VOLUME ["${APP_FILES}"]
# VOLUME ["${WORLD_FILES}"]

ENTRYPOINT ["/usr/bin/tini", "-s", "--"]

CMD ["/bin/bash", "-c", "$SCRIPTS/container/up.sh"]
