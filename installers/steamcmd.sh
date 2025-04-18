#!/usr/bin/env bash

echo "" >> /etc/environment
echo "# Steamcmd configuration" >> /etc/environment
echo "LD_LIBRARY_PATH=$STEAMCMD_PATH/linux32/:$LD_LIBRARY_PATH" >> /etc/environment

echo "\"$STEAMCMD_PATH/linux32/steamcmd\" \"\$@\"" >> /usr/local/bin/steamcmd
chmod +x "/usr/local/bin/steamcmd"

mkdir -p ${STEAMCMD_PATH}
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ${STEAMCMD_PATH}
ln -sf "$STEAMCMD_PATH/steamcmd.sh" /usr/local/bin/steamcmd
