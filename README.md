# Steam-based Dedicated Server Base Image

![Repo Image](/images/repo.png)

**_Teriyakidactyl Delivers!™_**

## Table of Contents
- [Steam-based Dedicated Server Base Image](#steam-based-dedicated-server-base-image)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Features](#features)
  - [Usage](#usage)
  - [Environment Variables and Arguments](#environment-variables-and-arguments)
    - [Base Variables and Arguments](#base-variables-and-arguments)
      - [Environment Variables](#environment-variables)
      - [Build Arguments](#build-arguments)
    - [SteamCMD Variables and Arguments](#steamcmd-variables-and-arguments)
      - [Environment Variables](#environment-variables-1)
      - [Build Arguments](#build-arguments-1)
    - [Emulation Variables and Arguments](#emulation-variables-and-arguments)
      - [Wine](#wine)
        - [Environment Variables](#environment-variables-2)
        - [Build Arguments](#build-arguments-2)
      - [Box86 and Box64](#box86-and-box64)
        - [Environment Variables](#environment-variables-3)
    - [Application Specific Variables and Arguments](#application-specific-variables-and-arguments)
      - [Environment Variables](#environment-variables-4)
    - [Container Specific Variables and Arguments](#container-specific-variables-and-arguments)
      - [Environment Variables](#environment-variables-5)
  - [File Structure](#file-structure)
    - [Directory Purposes](#directory-purposes)

## Introduction
This Docker image serves as a base for creating Steam-based dedicated game servers. It provides a common foundation for managing SteamCMD, emulation layers (Wine, Proton, Box86, Box64), and server operations, simplifying the process of setting up and maintaining game servers across different architectures.

## Features
- SteamCMD integration for server updates
- Cross-architecture support (x86_64, ARM)
- Emulation layer support (Wine, Proton, Box86, Box64)
- Non-root user execution for improved security
- Flexible configuration through environment variables and build arguments
- Multi-file logging system with color syntax highlighting

## Usage
To use this base image, extend it in your game-specific Dockerfile:

```dockerfile
FROM docker-steamcmd-server:latest

ENV
    # Add Application Specific Variables and Arguments (see below)
    # Add Container Specific Variables and Arguments (see below)
```

## Environment Variables and Arguments

Case notes: any ENV variables that will be visible in a running container should be `SCREAMING_SNAKE_CASE` and variables or args used only in the build process should be `snake_case`

### Base Variables and Arguments

#### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `DISPLAY` | X display | `:0` |
| `LOGS` | Directory for log files | `/var/log` |
| `PUID` | User ID for the non-root user | `1000` |
| `SCRIPTS` | Directory for utility scripts | `/usr/local/bin` |
| `TERM` | Terminal type | `xterm-256color` |

#### Build Arguments
| Argument | Description | Default |
|----------|-------------|---------|
| `debian_frontend` | Debian frontend configuration | `noninteractive` |
| `packages_base` | Base packages to install | (see Dockerfile) |
| `packages_base_build` | Base build packages to install | (see Dockerfile) |
| `packages_dev` | Development packages to install | (see Dockerfile) |
| `target_arch` | Target architecture for the build | |

### SteamCMD Variables and Arguments

#### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `STEAM_LIBRARY` | Steam library directory | `$APP_FILES/Steam` |
| `STEAMCMD_PATH` | Path to SteamCMD installation | `/opt/steamcmd` |
| `STEAMCMD_PROFILE` | SteamCMD profile directory | `/home/$APP_USER/Steam` |

#### Build Arguments
| Argument | Description | Default |
|----------|-------------|---------|
| `packages_amd64_only` | Packages required for AMD64 architecture | (see Dockerfile) |
| `packages_arm_only` | Packages required for ARM architecture | (see Dockerfile) |


### Emulation Variables and Arguments

#### Wine

##### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `WINE_PATH` | Path to Wine installation | `/opt/wine-staging/bin` |
| `WINEPREFIX` | Wine prefix directory | `/app/Wine` |

##### Build Arguments
| Argument | Description | Default |
|----------|-------------|---------|
| `WINE_BRANCH` | Wine branch to install | `staging` |
| `WINE_DIST` | Wine distribution | `bookworm` |
| `WINE_ID` | Wine ID | `debian` |
| `WINE_TAG` | Wine tag | `-1` |
| `WINE_VERSION` | Wine version to install | `9.13` |

#### Box86 and Box64

##### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `BOX86_LOG` | Box86 log level | `1` |
| `BOX86_TRACE_FILE` | Box86 trace file location | `$LOGS/box86.log` |
| `BOX64_LOG` | Box64 log level | `1` |
| `BOX64_TRACE_FILE` | Box64 trace file location | `$LOGS/box64.log` |

### Application Specific Variables and Arguments

#### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `APP_COMMAND` | Command to run the application | [conditional emulator syntax]/$APP_FILES/$APP_EXE |
| `APP_EXE` | Executable name of the server | |
| `APP_FILES` | Directory for application files | `/app` |
| `APP_NAME` | Name of the application/game server | |
| `APP_USER` | Username for the non-root user | $APP_NAME |
| `STEAM_CONAN_CLIENT_APPID` | SteamCMD Client (game) AppID download mods with | |
| `STEAM_SERVER_APPID` | SteamCMD AppID for dedicated server download | |
| `WORLD_FILES` | Directory for world/save files | `/world` |

### Container Specific Variables and Arguments

#### Environment Variables

This section shows probable variables that will be defined by derivitive containers.

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_PUBLIC` | Whether the server is public | `0` |
| `SERVER_PLAYER_PASS` | Server password | |
| `SERVER_NAME` | Server name | |
| `WORLD_NAME` | World/save name | |

## File Structure
```
/
├── app/
│   ├── Steam/
│   └── Wine/
├── home/
│   └── container/
│       └── Steam/
├── opt/
│   ├── steamcmd/
│   └── wine-staging/
│       └── bin/
├── usr/
│   └── local/
│       └── bin/
├── var/
│   └── log/
└── world/
```

### Directory Purposes

| Path | Variable | Description |
|------|----------|-------------|
| `/app` | `$APP_FILES` | Where SteamCMD will download the game server files to. **This is a volume mount point.** |
| `/app/Steam` | `$STEAM_LIBRARY` | Steam 'library', where SteamCMD will store modules (if relevant) |
| `/app/Wine` | `$WINEPREFIX` | Wine prefix for running Windows-based game servers (if applicable). |
| `/home/${APP_USER}` | `$HOME` | Home directory for the non-root user (named after the game/app), containing user-specific configurations and the Steam user profile. |
| `/home/${APP_USER}/Steam` | `$STEAMCMD_PROFILE` | User-specific Steam files and configurations. |
| `/opt/steamcmd` | `$STEAMCMD_PATH` | Contains the SteamCMD installation for managing game server updates. |
| `/opt/wine-staging/bin` | `$WINE_PATH` | Stores the Wine installation (if used) for running Windows applications. |
| `/usr/local/bin` | `$SCRIPTS` | Scripts and functions in support of the base image, and derivative containers |
| `/var/log` | `$LOGS` | Stores log files for the game server, SteamCMD, and other components, facilitating troubleshooting and monitoring. |
| `/world` | `$WORLD_FILES` | Stores world data, save files, and other persistent game-specific data that should be preserved across container restarts. **This is a volume mount point.** |


This structure separates application files, persistent data, tools, scripts, logs, and user-specific content, promoting organization and making it easier to manage volumes and updates. The use of environment variables for these paths allows for easier configuration and maintenance across different deployments.
