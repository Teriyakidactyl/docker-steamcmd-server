#!/usr/bin/env bash

set -Eeuo pipefail

[ -f /etc/environment ] && source /etc/environment

: "${TARGETARCH:?TARGETARCH is required}"
: "${BOX86_DEB_URL:?BOX86_DEB_URL is required}"
: "${BOX64_DEB_URL:?BOX64_DEB_URL is required}"

if [ "$TARGETARCH" != "arm64" ]; then
    echo "Box86/Box64 installer is only valid for arm64" >&2
    exit 1
fi

cat >> /etc/environment <<'EOF'

export BOX86_LOG=1
export BOX86_TRACE_FILE=${LOGS:-/var/log/container}/box86.log
export BOX64_LOG=1
export BOX64_DYNAREC=1
export BOX64_DYNAREC_BLEEDING_EDGE=0
export BOX64_DYNAREC_BIGBLOCK=0
export BOX64_DYNAREC_STRONGMEM=2
export BOX64_TRACE_FILE=${LOGS:-/var/log/container}/box64.log
export SDL_AUDIODRIVER=dummy
export ARCH_COMMAND_PREFIX=box64
EOF

if ! dpkg --print-foreign-architectures | grep -qx armhf; then
    dpkg --add-architecture armhf
    apt-get update
fi
apt-get install -y --no-install-recommends libc6:armhf

download_deb() {
    local url="$1"
    local destination="$2"
    curl --fail --show-error --silent --location \
        --retry 5 --retry-all-errors --connect-timeout 15 \
        "$url" --output "$destination"
    dpkg-deb --info "$destination" >/dev/null
}

download_deb "$BOX86_DEB_URL" /tmp/box86.deb
dpkg -i /tmp/box86.deb || apt-get -f install -y
rm -f /tmp/box86.deb

download_deb "$BOX64_DEB_URL" /tmp/box64.deb
dpkg -i /tmp/box64.deb || apt-get -f install -y
rm -f /tmp/box64.deb

command -v box86 >/dev/null
command -v box64 >/dev/null
