#!/usr/bin/env bash

echo "" >> /etc/environment
echo "# Steamcmd configuration" >> /etc/environment
echo "export LD_LIBRARY_PATH=$STEAMCMD_PATH/linux32" >> /etc/environment

mkdir -p ${STEAMCMD_PATH}
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ${STEAMCMD_PATH}
ln -sf "$STEAMCMD_PATH/steamcmd.sh" /usr/local/bin/steamcmd


# NOTE
# ILocalize::AddFile() failed to load file "public/steambootstrapper_english.txt"
# ^ is an error related to first-run where public doesn't yet exist.
