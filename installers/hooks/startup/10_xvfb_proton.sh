#!/bin/bash

# Xvfb launcher script for Proton
# Creates a virtual X server to run Proton-based applications
# Similar to the Wine version but with Proton-specific adjustments

log "Creating $APP_NAME xvfb-run Proton APP_COMMAND"

# Create the xvfb-run script for Proton
cat <<'EOF' > "$SCRIPTS/xvfb-run-proton.sh"
#!/bin/bash
# Set up minimal virtual framebuffer for Proton
xvfb-run \
  --auto-servernum \
  --server-args='-screen 0 640x480x24:32 -nolisten tcp' \
  $APP_COMMAND_PREFIX $APP_FILES/$APP_EXE $APP_ARGS
EOF

# Set permissions
chown -R ${CONTAINER_USER}:${CONTAINER_USER} "$SCRIPTS/xvfb-run-proton.sh"
chmod +x "$SCRIPTS/xvfb-run-proton.sh"

# Update the APP_COMMAND to use our wrapper
export APP_COMMAND="$SCRIPTS/xvfb-run-proton.sh"

# Set common Proton environment variables if they aren't already set
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:99
fi

# Disable GPU acceleration - not needed for server applications
if [ -z "$PROTON_NO_D3D11" ]; then
    export PROTON_NO_D3D11=1
fi

if [ -z "$PROTON_NO_D3D12" ]; then
    export PROTON_NO_D3D12=1 
fi

if [ -z "$PROTON_USE_WINED3D" ]; then
    export PROTON_USE_WINED3D=1
fi

log "Xvfb Proton launcher setup complete with virtual display $DISPLAY"