Focused Command Wrapper Implementation Roadmap
Overview

This roadmap outlines the implementation of architecture-specific command wrappers for the Docker SteamCMD Server project. The goal is to improve maintainability by moving architecture detection logic from runtime scripts to build-time configuration, focusing only on the most critical architecture-dependent commands.
Phase 1: Command Wrapper Design
1.1 Identify Key Architecture-Dependent Commands

We'll focus only on the two commands that require architecture-specific execution:

    steamcmd - For SteamCMD operations (requires Box86 on ARM)
    gameserver - For game server execution (requires Box64/Wine combinations on ARM)

1.2 Define Wrapper Script Structure

bash

#!/bin/bash
# Description: What this wrapper does
# Usage: command [args]

# Architecture-specific command execution
command_to_execute "$@"

Phase 2: Implementation in Dockerfile
2.1 Implement SteamCMD Wrapper

dockerfile

# Create steamcmd wrapper
RUN echo '#!/bin/bash' > /usr/local/bin/steamcmd && \
    echo '# Wrapper for steamcmd with architecture detection' >> /usr/local/bin/steamcmd && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        echo 'box86 $STEAMCMD_PATH/steamcmd.sh "$@"' >> /usr/local/bin/steamcmd; \
    else \
        echo '$STEAMCMD_PATH/steamcmd.sh "$@"' >> /usr/local/bin/steamcmd; \
    fi && \
    chmod +x /usr/local/bin/steamcmd

2.2 Implement Game Server Wrapper

dockerfile

# Create game server wrapper
RUN echo '#!/bin/bash' > /usr/local/bin/gameserver && \
    echo '# Wrapper for running game server executable with appropriate compatibility layer' >> /usr/local/bin/gameserver && \
    if [ "$TARGETARCH" = "arm64" ] && [ "$COMPAT_LAYER" = "wine" ]; then \
        echo 'box64 wine64 $APP_FILES/$APP_EXE "$@"' >> /usr/local/bin/gameserver; \
    elif [ "$COMPAT_LAYER" = "wine" ]; then \
        echo 'wine64 $APP_FILES/$APP_EXE "$@"' >> /usr/local/bin/gameserver; \
    elif [ "$COMPAT_LAYER" = "proton" ]; then \
        echo '/opt/proton/proton run $APP_FILES/$APP_EXE "$@"' >> /usr/local/bin/gameserver; \
    else \
        echo '$APP_FILES/$APP_EXE "$@"' >> /usr/local/bin/gameserver; \
    fi && \
    chmod +x /usr/local/bin/gameserver

Phase 3: Script and Environment Variable Updates
3.1 Update Server Initialization Script

Replace existing code:

bash

# Old code with runtime architecture detection
if echo "$ARCH" | grep -q "arm"; then
    log "Running on $ARCH, setting ENV"
    export APP_COMMAND="box64 wine64 $APP_FILES/$APP_EXE"
else
    export APP_COMMAND="wine64 $APP_FILES/$APP_EXE"
fi

With new wrapper approach:

bash

# Server start using wrapper
log "Starting game server with configuration parameters"
gameserver $SERVER_ARGS

3.2 Remove Unnecessary Environment Variables

In the Dockerfile, remove the APP_COMMAND_PREFIX environment variable:

dockerfile

# Remove this line
ENV APP_COMMAND_PREFIX="${APP_COMMAND_PREFIX}"

Also update the CI/CD pipeline in docker-build.yml to remove the APP_COMMAND_PREFIX build argument:

yaml

# Remove this section from build-args
APP_COMMAND_PREFIX=${{ env.APP_COMMAND_PREFIX }}

3.2 Update SteamCMD Functions

Replace:

bash

# Old update code
$STEAMCMD_PATH/steamcmd.sh \
+@sSteamCmdForcePlatformType windows \
+force_install_dir $APP_FILES \
+login anonymous \
+app_update $STEAM_SERVER_APPID \
validate \
+quit | log_stdout

With:

bash

# New update code using wrapper
steamcmd \
+@sSteamCmdForcePlatformType windows \
+force_install_dir $APP_FILES \
+login anonymous \
+app_update $STEAM_SERVER_APPID \
validate \
+quit | log_stdout

3.3 Update Mod Management

Replace:

bash

# Old mod downloading code
$STEAMCMD_PATH/steamcmd.sh \
+force_install_dir "$STEAM_LIBRARY" \
+login anonymous \
+workshop_download_item $STEAM_CONAN_CLIENT_APPID $MOD_ID \
+quit | log_stdout

With:

bash

# New mod downloading code using steamcmd wrapper
steamcmd \
+force_install_dir "$STEAM_LIBRARY" \
+login anonymous \
+workshop_download_item $STEAM_CONAN_CLIENT_APPID $MOD_ID \
+quit | log_stdout

Phase 4: Documentation and Testing
4.1 Update README.md

Add a section explaining the command wrappers:

markdown

## Architecture-Specific Command Wrappers

This container provides two command wrappers that automatically handle architecture-specific execution:

- `steamcmd`: Runs SteamCMD with proper emulation on ARM platforms
- `gameserver`: Runs the game server executable with appropriate compatibility layer

These wrappers abstract away the complexity of cross-architecture compatibility and provide a consistent interface for scripts regardless of the underlying platform.

4.2 Testing Plan

    Build images for multiple architectures
    Test both wrappers on AMD64 and ARM64 platforms
    Verify that all operations work correctly:
        Server updates via steamcmd
        Server startup via gameserver
        Workshop mod downloads via steamcmd

Implementation Timeline

    Week 1: Implement the two wrappers in Dockerfile
    Week 2: Update scripts to use wrappers
    Week 3: Testing across architectures

Benefits of This Approach

    Targeted Optimization: Focuses only on the most critical architecture-dependent commands
    Simplified Maintenance: Architecture-specific logic centralized at build time
    Improved Performance: Eliminates runtime architecture detection in critical paths
    Reduced Complexity: Minimal changes to existing codebase
    Cleaner Runtime Scripts: Operational scripts have consistent command interfaces
    Reduced Environment Variables: Eliminates the need for the APP_COMMAND_PREFIX variable
    Cleaner Dockerfile: Removes conditional logic that was previously needed at runtime

