#!/usr/bin/env bash

cat << 'EOT' >> /etc/environment

# Steamcmd configuration
export LD_LIBRARY_PATH=$STEAMCMD_PATH/linux32
EOT

# Add steamcmd alias to bash profile
cat << 'EOT' >> /home/${CONTAINER_USER}/.bashrc

# Steamcmd aliases and shortcuts
alias steamcmd="${STEAMCMD_PATH}/steamcmd.sh"
EOT

mkdir -p ${STEAMCMD_PATH}
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ${STEAMCMD_PATH}

# NOTE
# ILocalize::AddFile() failed to load file "public/steambootstrapper_english.txt"
# ^ is an error related to first-run where public doesn't yet exist.
