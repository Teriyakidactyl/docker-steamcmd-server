#!/usr/bin/env bash

set -Eeuo pipefail

[ -f /etc/environment ] && source /etc/environment

: "${TARGETARCH:?TARGETARCH is required}"
: "${PROTON_VERSION:?PROTON_VERSION is required}"

if [ "$TARGETARCH" != "amd64" ]; then
    echo "Proton images are currently supported only on amd64; use Wine for ARM64 Windows servers." >&2
    exit 1
fi

PROTON_PATH="${PROTON_PATH:-/opt/proton}"
WINEPREFIX="$APP_FILES/.compat/proton"
INSTALL_I386="${PROTON_INSTALL_I386:-false}"

case "${DEBIAN_VERSION_CODENAME:-}" in
    trixie*) LIBPNG_PACKAGE="libpng16-16t64" ;;
    *)       LIBPNG_PACKAGE="libpng16-16" ;;
esac

apt-get install -y --no-install-recommends \
    xvfb xauth fontconfig python3 libegl1 libfreetype6 "$LIBPNG_PACKAGE" \
    libjpeg62-turbo libglib2.0-0 libdbus-1-3 libnss3 libx11-6

if [ "$INSTALL_I386" = "true" ]; then
    dpkg --add-architecture i386
    apt-get update
    apt-get install -y --no-install-recommends \
        libfreetype6:i386 "${LIBPNG_PACKAGE}:i386" libjpeg62-turbo:i386 \
        libglib2.0-0:i386 libdbus-1-3:i386 libnss3:i386 libx11-6:i386
fi

VERSION_CLEANED="${PROTON_VERSION#GE-}"
VERSION_CLEANED="${VERSION_CLEANED#Proton}"
VERSION_CLEANED="${VERSION_CLEANED#-}"
VERSION_FORMATTED="${VERSION_CLEANED//./-}"
PROTON_TAG_NAME="GE-Proton${VERSION_FORMATTED}"
PROTON_VERSION_MAJOR="${VERSION_CLEANED%%.*}"
PROTON_ARCHIVE_NAME="${PROTON_TAG_NAME}.tar.gz"

# GE-Proton 11 introduced architecture-qualified release archives. Proton is
# currently amd64-only in this base, so select the x86_64 artifact for 11+.
if [[ "$PROTON_VERSION_MAJOR" =~ ^[0-9]+$ ]] && [ "$PROTON_VERSION_MAJOR" -ge 11 ]; then
    PROTON_ARCHIVE_NAME="${PROTON_TAG_NAME}-x86_64.tar.gz"
fi

PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_TAG_NAME}/${PROTON_ARCHIVE_NAME}"

mkdir -p "$PROTON_PATH" "$WINEPREFIX" /tmp/proton_ge
curl --fail --show-error --silent --location \
    --retry 5 --retry-all-errors --connect-timeout 15 \
    "$PROTON_URL" --output /tmp/proton_ge/proton.tar.gz
tar -tzf /tmp/proton_ge/proton.tar.gz >/dev/null
tar -xzf /tmp/proton_ge/proton.tar.gz -C /tmp/proton_ge
PROTON_SOURCE_DIR="$(find /tmp/proton_ge -mindepth 1 -maxdepth 1 -type d -name "${PROTON_TAG_NAME}*" -print -quit)"
if [ -z "$PROTON_SOURCE_DIR" ]; then
    echo "Unable to locate extracted Proton directory for ${PROTON_TAG_NAME}" >&2
    exit 1
fi
cp -a "${PROTON_SOURCE_DIR}/." "$PROTON_PATH/"
rm -rf /tmp/proton_ge

cat > /usr/local/bin/proton <<EOF
#!/bin/bash
exec "${PROTON_PATH}/proton" "\$@"
EOF
chmod 0755 /usr/local/bin/proton

cat >> /etc/environment <<EOF

export PROTON_PATH=${PROTON_PATH}
export PROTON_VERSION=${PROTON_VERSION}
export WINEPREFIX=${WINEPREFIX}
export WINEDEBUG=fixme-all
export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAMCMD_PATH}
export STEAM_COMPAT_DATA_PATH=${WINEPREFIX}
export PROTON_LOG=1
export PROTON_LOG_DIR=${LOGS}
export COMPAT_COMMAND="proton runinprefix"
export APP_USE_XVFB=true
EOF

mkdir -p "$HOOK_DIRECTORIES/pre-startup"
install -m 0755 /tmp/installers/hooks/pre-startup/20_proton_prefix.sh \
    "$HOOK_DIRECTORIES/pre-startup/20_proton_prefix.sh"
chown root:root "$HOOK_DIRECTORIES/pre-startup/20_proton_prefix.sh"

chown -R root:root "$PROTON_PATH"
chown -R "$CONTAINER_USER:$CONTAINER_USER" "$WINEPREFIX"
