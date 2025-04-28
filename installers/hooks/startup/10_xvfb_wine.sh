#!/bin/bash

log "Creating $APP_NAME xvfb-run APP_COMMAND"

# xvfb-run MAN: https://linux.die.net/man/1/xvfb

cat <<'EOF' > "$SCRIPTS/xvfb-run-wine.sh"
#!/bin/bash
xvfb-run \
  --auto-servernum \
  --server-args='-screen 0 640x480x24:32 -nolisten tcp' "$APP_COMMAND_PREFIX $APP_FILES/$APP_EXE $APP_ARGS"
EOF
chown -R ${CONTAINER_USER}:${CONTAINER_USER} "$SCRIPTS/xvfb-run-wine.sh"
chmod +x "$SCRIPTS/xvfb-run-wine.sh"

export APP_COMMAND="$SCRIPTS/xvfb-run-wine.sh"
