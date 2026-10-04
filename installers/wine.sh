#!/usr/bin/env bash

set -Eeuo pipefail

[ -f /etc/environment ] && source /etc/environment

: "${TARGETARCH:?TARGETARCH is required}"
: "${WINE_VERSION:?WINE_VERSION is required}"
: "${WINE_BRANCH:?WINE_BRANCH is required}"
: "${WINE_DIST:?WINE_DIST is required}"
: "${WINE_ID:?WINE_ID is required}"

INSTALL_I386="${WINE_INSTALL_I386:-false}"
WINE_PATH="/opt/wine-${WINE_BRANCH}/bin"
WINEPREFIX="${WINEPREFIX:-$APP_FILES/.compat/wine}"

WINE_VER_MAJOR="${WINE_VERSION%%.*}"
WINE_VER_MINOR="$(printf '%s' "$WINE_VERSION" | cut -d. -f2)"
WINE_VER_MINOR="${WINE_VER_MINOR:-0}"

if [ "$WINE_VER_MAJOR" -gt 10 ] || { [ "$WINE_VER_MAJOR" -eq 10 ] && [ "$WINE_VER_MINOR" -ge 2 ]; }; then
    WINEARCH="wow64"
    WINE_EXECUTABLE="wine"
else
    WINEARCH="win64"
    WINE_EXECUTABLE="wine64"
fi

case "$WINE_DIST" in
    trixie*) LIBPNG_PACKAGE="libpng16-16t64" ;;
    *)       LIBPNG_PACKAGE="libpng16-16" ;;
esac

PACKAGES_WINE="xvfb xauth fontconfig libegl1 libfreetype6 ${LIBPNG_PACKAGE} libjpeg62-turbo"
apt-get install -y --no-install-recommends $PACKAGES_WINE

if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" = "amd64" ] && [ "$WINEARCH" != "wow64" ]; then
    dpkg --add-architecture i386
    apt-get update
    apt-get install -y --no-install-recommends \
        libfreetype6:i386 "${LIBPNG_PACKAGE}:i386" libjpeg62-turbo:i386 \
        libglib2.0-0:i386 libgstreamer1.0-0:i386
elif [ "$INSTALL_I386" = "true" ]; then
    echo "WINE_INSTALL_I386 requested, but new WoW64/ARM builds do not require separate i386 Wine packages."
fi

cat >> /etc/environment <<EOF

export WINE_PATH=${WINE_PATH}
export WINEPREFIX=${WINEPREFIX}
export WINEARCH=${WINEARCH}
export WINEDEBUG=fixme-all
export WINE_LOG=1
export WINE_TRACE_FILE=/var/log/wine.log
export COMPAT_COMMAND=${WINE_EXECUTABLE}
export APP_USE_XVFB=true
EOF

mkdir -p "$WINE_PATH" "$WINEPREFIX" /tmp/wine_debs

WINE_POOL_DIR="wine"
[ "$WINE_BRANCH" = "staging" ] && WINE_POOL_DIR="wine-staging"
WINEHQ_REPO_URL="https://dl.winehq.org/wine-builds/${WINE_ID}/pool/main/w/${WINE_POOL_DIR}/"

WINE_64_MAIN_BIN="wine-${WINE_BRANCH}-amd64_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"
WINE_64_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_amd64.deb"

download_deb() {
    local filename="$1"
    curl --fail --show-error --silent --location \
        --retry 5 --retry-all-errors --connect-timeout 15 \
        "${WINEHQ_REPO_URL}${filename}" \
        --output "/tmp/wine_debs/${filename}"
    dpkg-deb --info "/tmp/wine_debs/${filename}" >/dev/null
}

download_deb "$WINE_64_MAIN_BIN"
download_deb "$WINE_64_SUPPORT_BIN"
dpkg-deb -x "/tmp/wine_debs/$WINE_64_MAIN_BIN" /
dpkg-deb -x "/tmp/wine_debs/$WINE_64_SUPPORT_BIN" /

if [ "$INSTALL_I386" = "true" ] && [ "$TARGETARCH" = "amd64" ] && [ "$WINEARCH" != "wow64" ]; then
    WINE_32_MAIN_BIN="wine-${WINE_BRANCH}-i386_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"
    WINE_32_SUPPORT_BIN="wine-${WINE_BRANCH}_${WINE_VERSION}~${WINE_DIST}${WINE_TAG}_i386.deb"
    download_deb "$WINE_32_MAIN_BIN"
    download_deb "$WINE_32_SUPPORT_BIN"
    dpkg-deb -x "/tmp/wine_debs/$WINE_32_MAIN_BIN" /
    dpkg-deb -x "/tmp/wine_debs/$WINE_32_SUPPORT_BIN" /
fi

rm -rf /tmp/wine_debs

ln -sf "$WINE_PATH/$WINE_EXECUTABLE" "/usr/local/bin/$WINE_EXECUTABLE"
ln -sf "$WINE_PATH/wineboot" /usr/local/bin/wineboot
ln -sf "$WINE_PATH/winecfg" /usr/local/bin/winecfg
ln -sf "$WINE_PATH/wineserver" /usr/local/bin/wineserver

mkdir -p "$HOOK_DIRECTORIES/pre-startup"
install -m 0755 /tmp/installers/hooks/pre-startup/20_wine_prefix.sh \
    "$HOOK_DIRECTORIES/pre-startup/20_wine_prefix.sh"
chown root:root "$HOOK_DIRECTORIES/pre-startup/20_wine_prefix.sh"

chown -R "$CONTAINER_USER:$CONTAINER_USER" "$WINEPREFIX"
chmod 0755 "$WINE_PATH/$WINE_EXECUTABLE" "$WINE_PATH/wineboot" "$WINE_PATH/winecfg" "$WINE_PATH/wineserver"
