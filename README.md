# Steam-based Dedicated Server Base Image

Common runtime for TeriyakiDactyl Steam dedicated-server images.

## What the base provides

- SteamCMD installation and update-on-start with retries
- Debian amd64 and arm64 images
- Box86/Box64 support on arm64
- Wine staging/stable variants on amd64 and arm64
- Experimental GE-Proton variants on amd64
- Non-root game execution under Tini
- Ordered lifecycle hooks
- PID-file health checks and process-group shutdown
- Persistent Steam and Wine/Proton state under `/app`

## Derivative image contract

A native Linux server normally needs:

```dockerfile
ARG BASE_TAG=trixie
FROM ghcr.io/teriyakidactyl/docker-steamcmd-server:${BASE_TAG}

ENV APP_NAME="example" \
    APP_EXE="example_server" \
    STEAM_SERVER_APPID="123456" \
    STEAM_PLATFORM_TYPE="linux"
```

A Windows server should use a Wine base tag such as `trixie_wine-staging` and set `STEAM_PLATFORM_TYPE=windows`.

### Application variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `APP_NAME` | empty | Application identifier |
| `APP_FILES` | `/app` | Steam install directory |
| `APP_EXE` | empty | Executable path relative to `APP_FILES`; nested paths are supported |
| `APP_EXECUTABLE` | empty | Optional absolute executable path |
| `APP_LOG_NAME` | executable basename | Log filename under `/var/log` |
| `APP_ARGS_FILE` | empty | Preferred argument file: one argument per line, expanded with `envsubst` |
| `APP_ARGS` | empty | Legacy shell-string arguments for existing child images |
| `APP_COMMAND` | empty | Legacy complete command override |
| `APP_USE_XVFB` | `false` | Run through an Xvfb virtual display |
| `APP_PID_FILE` | `/tmp/container/app.pid` | PID used by the generic health check |
| `SHUTDOWN_TIMEOUT` | `10` | Seconds before the process group is force-killed |
| `APP_STOP_SIGNAL` | `TERM` | Signal forwarded to the application process group during container shutdown |

New images should use `APP_ARGS_FILE`. Each non-comment line is one argument, so an expanded value such as a server name containing spaces remains one argument.

Example:

```text
-name
$SERVER_NAME
-port
$SERVER_PORT
```

### SteamCMD variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `STEAM_SERVER_APPID` | empty | Dedicated-server AppID |
| `STEAM_PLATFORM_TYPE` | `linux` | Steam platform type, typically `linux` or `windows` |
| `UPDATE_ON_START` | `true` | Run SteamCMD `app_update` before launch |
| `STEAM_VALIDATE` | `false` | Add `validate` to the update |
| `STEAMCMD_RETRIES` | `5` | Update attempts |
| `STEAMCMD_PATH` | `/opt/steamcmd` | SteamCMD installation |
| `STEAMCMD_PROFILE` | `/app/.steam/profile` | Persistent Steam state |
| `STEAM_LIBRARY` | `/app/.steam/library` | Persistent Steam/workshop cache |

SteamCMD update failures are fatal; the application is not launched after an incomplete update.

### Compatibility layers

The runtime composes launches in this order:

```text
Xvfb -> ARCH_COMMAND_PREFIX -> COMPAT_COMMAND -> executable -> arguments
```

On arm64, `ARCH_COMMAND_PREFIX=box64` for 64-bit game processes. SteamCMD's 32-bit client is launched through Box64's Box32 mode while Valve's launcher retains its self-update/restart behavior. Box86 remains installed for derivative images that need it. Wine variants set `COMPAT_COMMAND=wine` (or `wine64` for older Wine). Keeping these separate also allows Wine helper tools such as `wineboot` to run correctly through Box64.

Wine prefixes are persisted in `/app/.compat/wine`. Proton compatibility data is persisted in `/app/.compat/proton`, with Proton's Windows prefix under `pfx/`.

Prefix initialization is completion-marked rather than inferred from a non-empty directory. If an earlier initialization was interrupted, the next start retries it non-destructively and writes the readiness marker only after the compatibility layer passes an operational check. `COMPAT_PREFIX_TIMEOUT` controls the initialization/verification ceiling in seconds and defaults to `300`.

Wine prefix initialization defaults `WINE_BOOT_DLL_OVERRIDES` to `mscoree,mshtml=` so optional Wine Mono/Gecko installer dialogs cannot block a headless first boot. A derivative that intentionally manages those components may set `WINE_BOOT_DLL_OVERRIDES` explicitly, including to an empty value.

Proton is currently amd64-only. ARM64 Windows dedicated servers should use a Wine variant. GE-Proton 11+ is launched with `PROTON_USE_WOW64=1` so its current multi-arch Wine layout uses the new WoW64 loader path consistently across supported Debian bases.

The support matrix carries one stable Wine line and one staging Wine line per Debian base. WineHQ discontinued Bookworm packages after 11.10, so Bookworm staging remains on 11.10 while Trixie staging follows the current development release. WineHQ's current Bookworm/Trixie packaging is split by PE architecture; the image extracts the i386 PE payload as well as the amd64 payload for new-WoW64 prefixes, without installing a separate 32-bit Unix runtime.

## Persistence

| Path | Purpose |
| --- | --- |
| `/app` | Game files, Steam state, compatibility prefixes |
| `/world` | Saves and administrator-owned game configuration |
| `/var/log/container` | Writable runtime logs; normally ephemeral |

Derivative images should link game-specific save/configuration locations into `/world`.

## Hooks

Hooks live under `/usr/local/bin/container/hooks`. Supported hook directories include `pre-startup`, `startup`, `shutdown`, `hourly`, `daily`, `weekly`, and `monthly`.

`pre-startup` and `startup` are strict: a failing hook prevents launch. Scheduled and shutdown hooks are best-effort. Game images should use numbered hooks such as `30_game_config.sh`, leaving the lower numbers for base initialization.

## Tags

The build matrix publishes fully versioned tags, stable codename aliases such as `trixie_wine-staging`, architecture-specific build tags, and detailed arm64 tags that include Box86/Box64 versions.

Development tags use `_dev` before the architecture suffix.

## Build-time settings and reproducibility

`CONTAINER_UID` defaults to `1000`. It is a build argument; this image does not pretend to provide runtime UID remapping.

The base pins the `docker-up` helper checkout with `DOCKER_UP_REF`, while the process supervisor itself is maintained in this repository. Runtime scripts are root-owned and not writable by the game account.

Binary downloads use fail-fast/retry behavior and validate archive/package structure before extraction. Box86/Box64 sources are commit-pinned.

## Development

GitHub Actions runs Bash syntax checks, ShellCheck, prefix-hook regression tests, matrix-generator unit tests, Hadolint, the full architecture/compatibility build matrix, and manifest creation. Every Wine and Proton matrix row must initialize a clean compatibility prefix through the same pre-start hook used in production before a push run may publish its architecture tags.

`tests/compat-prefix-smoke.sh IMAGE PLATFORM TYPE` runs that compatibility-prefix gate locally for a built image, where `TYPE` is `wine` or `proton`. `tests/containers.sh` derives its broader tag list from the same matrix generator.

Pull-request and manual-dispatch runs validate without publishing. Only push events on the configured publication branches may push architecture tags and create manifests.
