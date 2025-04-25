BOX64_DEB_URL: "https://github.com/ryanfortner/box64-debs/raw/a6c4fb3f1a4773b6318d3f66e56c119f40f17a87/debian/box64_0.3.5+20250416.96080e4-1_arm64.deb"

https://api.github.com/repos/ptitSeb/box64/commits/96080e4

# Add Box86/Box64 configuration to environment file
cat << EOT >> /etc/environment

# Box86/Box64 configuration
# Box86 configuration
export BOX86_LOG=1
export BOX86_TRACE_FILE=/var/log/box86.log
export DEBUGGER=box86

# Box64 configuration
export BOX64_LOG=1
export BOX64_DYNAREC_BLEEDING_EDGE=0
export BOX64_DYNAREC_BIGBLOCK=0
export BOX64_DYNAREC_STRONGMEM=2
export BOX64_TRACE_FILE=/var/log/box64.log
EOT


04/24/2025 19:34:15 [startup_script.sh]: Unexpanded variables found in APP_ARGS - expanding now
04/24/2025 19:34:15 [startup_script.sh]: APP_ARGS expanded successfully
04/24/2025 19:34:15 [startup_script.sh]: DEBUG: APP_ARGS=-nographics -batchmode -name TestServer -port 2456 -public 0 -world TestWorld -password testpassword -savedir /world -saveinterval 1800
04/24/2025 19:34:15 [up.sh]: --------------------------------
04/24/2025 19:34:15 [up.sh]: Launching application: valheim
04/24/2025 19:34:15 [up.sh]: box64 /app/valheim_server.x86_64
04/24/2025 19:34:15 [up.sh]: -nographics
04/24/2025 19:34:15 [up.sh]: -batchmode
04/24/2025 19:34:15 [up.sh]: -name TestServer
04/24/2025 19:34:15 [up.sh]: -port 2456
04/24/2025 19:34:16 [up.sh]: -public 0
04/24/2025 19:34:16 [up.sh]: -world TestWorld
04/24/2025 19:34:16 [up.sh]: -password testpassword
04/24/2025 19:34:16 [up.sh]: -savedir /world
04/24/2025 19:34:16 [up.sh]: -saveinterval 1800
04/24/2025 19:34:16 [up.sh]: --------------------------------
04/24/2025 19:34:16 [box86.log]: Warning: Weak Symbol _ZGTtnaj not found, cannot apply R_386_JMP_SLOT 0x60459384 (0x6f790)
04/24/2025 19:02:49 [dpkg.log]: status half-configured libc-bin:arm64 2.41-7
04/24/2025 19:02:12 [history.log]: 
04/24/2025 19:34:16 [box86.log]: Using emulated /opt/steamcmd/linux32/steamclient.so
04/24/2025 19:02:49 [dpkg.log]: status installed libc-bin:arm64 2.41-7
04/24/2025 19:34:16 [history.log]: Commandline: apt-get install -y --no-install-recommends libc6:armhf
04/24/2025 19:34:16 [box86.log]: Warning: Global Symbol ZSTD_trace_decompress_end not found, cannot apply R_386_GLOB_DAT @0x68623328 ((nil)) in /opt/steamcmd/linux32/steamclient.so
04/24/2025 19:02:49 [dpkg.log]: startup packages purge
04/24/2025 19:34:16 [history.log]: Install: libc6:armhf (2.41-7), gcc-14-base:armhf (14.2.0-19, automatic), libgcc-s1:armhf (14.2.0-19, automatic)
04/24/2025 19:34:16 [box86.log]: Warning: Global Symbol ZSTD_trace_compress_begin not found, cannot apply R_386_GLOB_DAT @0x68623320 ((nil)) in /opt/steamcmd/linux32/steamclient.so
04/24/2025 19:02:49 [dpkg.log]: purge perl:arm64 5.40.1-3 <none>
04/24/2025 19:02:21 [history.log]: 
04/24/2025 19:34:16 [box86.log]: Warning: Global Symbol ZSTD_trace_decompress_begin not found, cannot apply R_386_GLOB_DAT @0x6862332c ((nil)) in /opt/steamcmd/linux32/steamclient.so
04/24/2025 19:02:49 [dpkg.log]: status config-files perl:arm64 5.40.1-3
04/24/2025 19:02:47 [history.log]: 
04/24/2025 19:34:16 [box86.log]: Warning: Global Symbol ZSTD_trace_compress_end not found, cannot apply R_386_GLOB_DAT @0x68623324 ((nil)) in /opt/steamcmd/linux32/steamclient.so
04/24/2025 19:02:49 [dpkg.log]: status not-installed perl:arm64 <none>
04/24/2025 19:34:16 [history.log]: Commandline: apt-get autoremove --purge -y git
04/24/2025 19:02:49 [dpkg.log]: purge git:arm64 1:2.47.2-0.1 <none>
04/24/2025 19:34:16 [box86.log]: Warning: Weak Symbol _ZGTtnaj not found, cannot apply R_386_JMP_SLOT 0x685758d0 (0xd83c70)
04/24/2025 19:34:16 [history.log]: Purge: libperl5.40:arm64 (5.40.1-3), libgdbm-compat4t64:arm64 (1.24-2), git:arm64 (1:2.47.2-0.1), perl:arm64 (5.40.1-3), libexpat1:arm64 (2.7.1-1), libgdbm6t64:arm64 (1.24-2), liberror-perl:arm64 (0.17030-1), perl-modules-5.40:arm64 (5.40.1-3), git-man:arm64 (1:2.47.2-0.1)
04/24/2025 19:02:49 [dpkg.log]: status config-files git:arm64 1:2.47.2-0.1
04/24/2025 19:34:16 [box86.log]: Error loading needed lib libSDL3.so.0
04/24/2025 19:02:50 [history.log]: 
04/24/2025 19:02:50 [dpkg.log]: status not-installed git:arm64 <none>
04/24/2025 19:34:16 [box86.log]: Warning: Cannot dlopen("libSDL3.so.0"/0x666c58a9, 2)
04/24/2025 19:02:50 [dpkg.log]: startup packages configure
04/24/2025 19:34:16 [box86.log]: Sigfault/Segbus while quitting, exiting silently
04/24/2025 19:34:17 [valheim_server.x86_64.log]: [UnityMemory] Configuration Parameters - Can be set up in boot.config
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-bucket-allocator-granularity=16"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-bucket-allocator-bucket-count=8"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-bucket-allocator-block-size=4194304"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-bucket-allocator-block-count=1"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-main-allocator-block-size=16777216"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-thread-allocator-block-size=16777216"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-gfx-main-allocator-block-size=16777216"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-gfx-thread-allocator-block-size=16777216"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-cache-allocator-block-size=4194304"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-typetree-allocator-block-size=2097152"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-profiler-bucket-allocator-granularity=16"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-profiler-bucket-allocator-bucket-count=8"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-profiler-bucket-allocator-block-size=4194304"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-profiler-bucket-allocator-block-count=1"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-profiler-allocator-block-size=16777216"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-profiler-editor-allocator-block-size=1048576"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-main=4194304"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-job-temp-allocator-block-size=2097152"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-job-temp-allocator-block-size-background=1048576"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-job-temp-allocator-reduction-small-platforms=262144"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-allocator-temp-initial-block-size-main=262144"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-allocator-temp-initial-block-size-worker=262144"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-background-worker=32768"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-job-worker=262144"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-preload-manager=262144"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-nav-mesh-worker=65536"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-audio-worker=65536"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-cloud-worker=32768"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: "memorysetup-temp-allocator-size-gfx=262144"
04/24/2025 19:34:17 [valheim_server.x86_64.log]: Mono path[0] = '/app/valheim_server_Data/Managed'
04/24/2025 19:34:17 [valheim_server.x86_64.log]: Mono config path = '/app/valheim_server_Data/MonoBleedingEdge/etc'
04/24/2025 19:34:17 [valheim_server.x86_64.log]: Preloaded 'libDiskSpacePlugin.so'
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Preloaded 'libsteam_api.so'
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Unable to preload the following plugins:
04/24/2025 19:34:18 [valheim_server.x86_64.log]: libparty.so
04/24/2025 19:34:18 [valheim_server.x86_64.log]: [PhysX] Initialized MultithreadedTaskDispatcher with 4 workers.
04/24/2025 19:34:18 [valheim_server.x86_64.log]: PlayerPrefs - Creating folder: /home/container/.config/unity3d/IronGate
04/24/2025 19:34:18 [valheim_server.x86_64.log]: PlayerPrefs - Creating folder: /home/container/.config/unity3d/IronGate/Valheim
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Unable to load player prefs
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Initialize engine version: 2022.3.50f1 (c3db7f8bf9b1)
04/24/2025 19:34:18 [valheim_server.x86_64.log]: [Subsystems] Discovering subsystems at path /app/valheim_server_Data/UnitySubsystems
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Forcing GfxDevice: Null
04/24/2025 19:34:18 [valheim_server.x86_64.log]: GfxDevice: creating device client; threaded=0; jobified=0
04/24/2025 19:34:18 [valheim_server.x86_64.log]: NullGfxDevice:
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Version: NULL 1.0 [1.0]
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Renderer: Null Device
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Vendor: Unity Technologies
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Begin MonoManager ReloadAssembly
04/24/2025 19:34:18 [valheim_server.x86_64.log]: - Loaded All Assemblies, in 0.538 seconds
04/24/2025 19:34:18 [valheim_server.x86_64.log]: - Finished resetting the current domain, in 0.013 seconds
04/24/2025 19:34:18 [valheim_server.x86_64.log]: ERROR: Shader Sprites/Default shader is not supported on this GPU (none of subshaders/fallbacks are suitable)
04/24/2025 19:34:18 [valheim_server.x86_64.log]: ERROR: Shader Sprites/Mask shader is not supported on this GPU (none of subshaders/fallbacks are suitable)
04/24/2025 19:34:18 [valheim_server.x86_64.log]: There is no texture data available to upload.
04/24/2025 19:34:18 [valheim_server.x86_64.log]: [PhysX] Initialized MultithreadedTaskDispatcher with 4 workers.
04/24/2025 19:34:18 [valheim_server.x86_64.log]: UnloadTime: 19.365600 ms
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Set background loading budget to Low
04/24/2025 19:34:18 [valheim_server.x86_64.log]: Loading first scene
04/24/2025 19:34:19 [valheim_server.x86_64.log]: ERROR: Shader GUI/Text Shader shader is not supported on this GPU (none of subshaders/fallbacks are suitable)
04/24/2025 19:34:19 [valheim_server.x86_64.log]: ERROR: Shader TextMeshPro/Mobile/Distance Field shader is not supported on this GPU (none of subshaders/fallbacks are suitable)
04/24/2025 19:34:19 [valheim_server.x86_64.log]: WARNING: Shader Unsupported: 'TextMeshPro/Distance Field' - All subshaders removed
04/24/2025 19:34:19 [valheim_server.x86_64.log]: WARNING: Shader Did you use #pragma only_renderers and omit this platform?
04/24/2025 19:34:19 [valheim_server.x86_64.log]: WARNING: Shader If subshaders removal was intentional, you may have forgotten turning Fallback off?
04/24/2025 19:34:19 [valheim_server.x86_64.log]: ERROR: Shader TextMeshPro/Distance Field shader is not supported on this GPU (none of subshaders/fallbacks are suitable)
04/24/2025 19:34:19 [valheim_server.x86_64.log]: WARNING: Shader Unsupported: 'TextMeshPro/Distance Field' - All subshaders removed
04/24/2025 19:34:19 [valheim_server.x86_64.log]: WARNING: Shader Did you use #pragma only_renderers and omit this platform?
04/24/2025 19:34:19 [valheim_server.x86_64.log]: WARNING: Shader If subshaders removal was intentional, you may have forgotten turning Fallback off?
04/24/2025 19:34:20 [valheim_server.x86_64.log]: Unloading 4 Unused Serialized files (Serialized files now loaded: 8)
04/24/2025 19:34:20 [valheim_server.x86_64.log]: [PhysX] Initialized MultithreadedTaskDispatcher with 4 workers.
04/24/2025 19:34:20 [valheim_server.x86_64.log]: UnloadTime: 3.612600 ms
04/24/2025 19:34:20 [valheim_server.x86_64.log]: ERROR: Shader TextMeshPro/Mobile/Distance Field shader is not supported on this GPU (none of subshaders/fallbacks are suitable)
04/24/2025 19:34:19 [valheim_server.x86_64.log]: Fetching PlatformPrefs 'GuiScale' before loading defaults
04/24/2025 19:34:19 [valheim_server.x86_64.log]: Fetching PlatformPrefs 'GuiScale' before loading defaults
04/24/2025 19:34:19 [valheim_server.x86_64.log]: Fetching PlatformPrefs 'ControllerLayout' before loading defaults
04/24/2025 19:34:19 [valheim_server.x86_64.log]: Initializing loading indicator instance
04/24/2025 19:34:20 [valheim_server.x86_64.log]: Unloading 173 unused Assets to reduce memory usage. Loaded Objects now: 2241.
04/24/2025 19:34:20 [valheim_server.x86_64.log]: Total: 18.380640 ms (FindLiveObjects: 0.749880 ms CreateObjectMapping: 0.373600 ms MarkObjects: 14.601560 ms DeleteObjects: 2.520600 ms)
04/24/2025 19:34:19 [valheim_server.x86_64.log]: Starting to load scene:start.unity (169d7618616154c03be07e9ad3af5893)
04/24/2025 19:34:19 [valheim_server.x86_64.log]: Set background loading budget to Normal
/usr/local/bin/container/up.sh: line 124:  4349 Segmentation fault      (core dumped) $APP_COMMAND >> $LOGS/$APP_EXE.log 2>&1
04/24/2025 19:35:16 [main]: ERROR - box64 /app/valheim_server.x86_64 -nographics -batchmode -name TestServer -port 2456 -public 0 -world TestWorld -password testpassword -savedir /world -saveinterval 1800 @PID 4349 appears to have died! Container Uptime: 0d 0h 2m
04/24/2025 19:35:16 [main]: Received signal: 1
04/24/2025 19:35:16 [shutdown]: Performing graceful shutdown...
04/24/2025 19:35:16 [shutdown]: Stopping tail processes...
04/24/2025 19:35:16 [shutdown]: Cleanup complete. Exiting.
