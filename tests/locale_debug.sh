#!/bin/bash
# Script to fix Perl locale warnings in Debian containers
# Usage: ./fix-locales.sh

# Exit on error
set -e

# Print commands before execution
set -x

# Install locales package if not already installed
if ! dpkg -l | grep -q locales; then
  apt-get update
  apt-get install -y locales
fi

# Uncomment the en_US.UTF-8 locale in locale.gen
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen

# Generate the locales
locale-gen

# Set environment variables
update-locale LANG=en_US.UTF-8
echo "LC_ALL=en_US.UTF-8" > /etc/environment
echo "LANG=en_US.UTF-8" >> /etc/environment
echo "LANGUAGE=en_US.UTF-8" >> /etc/environment

# Set current shell environment
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# Verify the locale settings
echo "Locale settings updated successfully:"
locale

echo "Perl locale warnings should now be fixed."