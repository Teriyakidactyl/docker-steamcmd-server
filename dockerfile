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
    SCRIPTS="/usr/local/bin" \
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
    # The WINEARCH value will be determined by the wine installer script based on version
    \
    # Package definitions with minimal base packages
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
        btop \
        nano" \
    \
    # Package definitions with detailed comments for maintainers
    PACKAGES_AMD64_ONLY="\
        # required for steamcmd
        lib32gcc-s1"

# Copy installer scripts and runtime scripts
COPY installers /tmp/installers
COPY --chown=${CONTAINER_USER}:${CONTAINER_USER} scripts ${SCRIPTS}

RUN set -eux && \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  USER SETUP                                                                                                          " && \
    echo "=======================================================================================================================================================================" && \
    useradd -m -u $PUID -d "/home/$CONTAINER_USER" -s /bin/bash $CONTAINER_USER && \
    \
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
    apt-get install -y --no-install-recommends $PACKAGES_BASE && \
    if echo "$BUILD_VERSION" | grep -q "_dev"; then \
        echo "Installing development packages..." && \
        apt-get install -y --no-install-recommends $PACKAGES_DEV; \
    fi && \
    \
    echo "=======================================================================================================================================================================" && \
    echo "                                                  STEAMCMD SETUP                                                                                                      " && \
    echo "=======================================================================================================================================================================" && \
    mkdir -p ${STEAMCMD_PATH} && \
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ${STEAMCMD_PATH} && \
    ln -sf "$STEAMCMD_PATH/steamcmd.sh" /usr/local/bin/steamcmd && \
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
        # Run the boxes installer script (self-contained with package variables)
        chmod +x /tmp/installers/*.sh && \
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
    # Clean up installers after all installations are complete    
    rm -rf /tmp/installers && \
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
    find ~ -type d -exec ls -ld {} \;

# Switch to the container user
USER ${CONTAINER_USER}

# TODO insert derivative container examples

# Expose application volumes
# VOLUME ["${APP_FILES}"]
# VOLUME ["${WORLD_FILES}"]

# CMD ["up.sh"]
