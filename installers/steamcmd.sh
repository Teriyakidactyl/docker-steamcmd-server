#!/usr/bin/env bash

# This worked
export LD_LIBRARY_PATH="$STEAMCMD_PATH/linux32/:$LD_LIBRARY_PATH"
box86 $STEAMCMD_PATH/linux32/steamcmd "$@"

# # Set file descriptor limit
# ulimit -n 2048

# # Define the exit code that triggers a restart
# MAGIC_RESTART_EXITCODE=42

# # Save original environment variables
# ORIGINAL_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
# ORIGINAL_LD_PRELOAD="$LD_PRELOAD"

# # Set the modified environment
# export LD_LIBRARY_PATH="$STEAMCMD_PATH/linux32/:$LD_LIBRARY_PATH"

# # Run steamcmd through box86
# if [ "$DEBUGGER" == "gdb" ] || [ "$DEBUGGER" == "cgdb" ]; then
#   ARGSFILE=$(mktemp $USER.steam.gdb.XXXX)
#   # Set the LD_PRELOAD varname in the debugger, and unset the global version.
#   if [ "$LD_PRELOAD" ]; then
#     echo set env LD_PRELOAD=$LD_PRELOAD >> "$ARGSFILE"
#     echo show env LD_PRELOAD >> "$ARGSFILE"
#     unset LD_PRELOAD
#   fi
#   $DEBUGGER -x "$ARGSFILE" box86 $STEAMCMD_PATH/linux32/steamcmd "$@"
#   rm "$ARGSFILE"
# else
#   box86 $STEAMCMD_PATH/linux32/steamcmd "$@"
# fi

# # Get the exit status
# STATUS=$?

# # Restore original environment
# if [ -z "$ORIGINAL_LD_LIBRARY_PATH" ]; then
#     unset LD_LIBRARY_PATH
# else
#     export LD_LIBRARY_PATH="$ORIGINAL_LD_LIBRARY_PATH"
# fi

# if [ -z "$ORIGINAL_LD_PRELOAD" ]; then
#     unset LD_PRELOAD
# else
#     export LD_PRELOAD="$ORIGINAL_LD_PRELOAD"
# fi

# # Check if we need to restart
# if [ $STATUS -eq $MAGIC_RESTART_EXITCODE ]; then
#     exec "$0" "$@"
# fi

# # Exit with the same status code
# exit $STATUS
