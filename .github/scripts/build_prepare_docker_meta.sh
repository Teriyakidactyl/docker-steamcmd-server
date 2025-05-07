#!/bin/bash
set -e
set -o pipefail
set -x # <--- Add this for trace mode

# Purpose: Prepare Docker metadata, tags, labels, and build arguments for a single build matrix combination.
# Sets various environment variables for use in subsequent steps (docker metadata, docker build).

# Input environment variables (expected from workflow env block):
# - INPUT_PLATFORM (e.g., linux/amd64)
# - INPUT_BOX86_MATRIX_ENTRY (e.g., {"0.3.9-d0aad67":"https://..."} or empty if not ARM)
# - INPUT_BOX64_MATRIX_ENTRY (e.g., {"0.3.5-3542c88":"https://..."} or empty if not ARM)
# - INPUT_IMAGE_TAG_BASE (e.g., bookworm-20250407-slim)
# - INPUT_COMPAT_LAYER_NAME (e.g., wine-staging-10.5, proton-9.27, native)
# - GITHUB_REF (automatically available)
# - PROTON_VERSION_GLOBAL (global env var from workflow)
# - WINE_ID (global env var from workflow)
# - WINE_TAG (global env var from workflow)


# --- Function Definitions ---

# Extracts the architecture (amd64, arm64) from the platform string
extract_architecture() {
  # Strip "linux/" prefix
  IMAGE_ARCHITECTURE_VAL=$(echo "${INPUT_PLATFORM}" | cut -d'/' -f2)
  echo "IMAGE_ARCHITECTURE=${IMAGE_ARCHITECTURE_VAL}" >> "$GITHUB_ENV"
  echo "Determined IMAGE_ARCHITECTURE: ${IMAGE_ARCHITECTURE_VAL}"
}

# Processes Box86/Box64 versions if on ARM architecture
process_box_versions() {
  if [[ "${IMAGE_ARCHITECTURE_VAL}" == "arm64" ]]; then
    if [[ -n "${INPUT_BOX86_MATRIX_ENTRY}" && "${INPUT_BOX86_MATRIX_ENTRY}" != "{}" ]]; then
      # Assuming INPUT_BOX86_MATRIX_ENTRY is like {"key":"value"}
      # Extract key (version) and value (URL)
      # This is a bit tricky with bash and json string, simpler if input was just key=value
      # For {"key":"value"}, use jq if available, or regex
      if echo "${INPUT_BOX86_MATRIX_ENTRY}" | grep -qE '"([^"]+)":"([^"]+)"'; then
          BOX86_VERSION_FINAL_VAL=$(echo "${INPUT_BOX86_MATRIX_ENTRY}" | sed -n 's/.*"\([^"]*\)":"\([^"]*\)".*/\1/p')
          BOX86_DEB_URL_FINAL_VAL=$(echo "${INPUT_BOX86_MATRIX_ENTRY}" | sed -n 's/.*"\([^"]*\)":"\([^"]*\)".*/\2/p')

          echo "BOX86_VERSION_FINAL=${BOX86_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
          echo "BOX86_DEB_URL_FINAL=${BOX86_DEB_URL_FINAL_VAL}" >> "$GITHUB_ENV"
          echo "Using Box86 version: ${BOX86_VERSION_FINAL_VAL}"
      else
          echo "Warning: Could not parse INPUT_BOX86_MATRIX_ENTRY: ${INPUT_BOX86_MATRIX_ENTRY}"
      fi
    else
      echo "No Box86 entry for ARM, or entry is empty."
    fi

    if [[ -n "${INPUT_BOX64_MATRIX_ENTRY}" && "${INPUT_BOX64_MATRIX_ENTRY}" != "{}" ]]; then
       if echo "${INPUT_BOX64_MATRIX_ENTRY}" | grep -qE '"([^"]+)":"([^"]+)"'; then
          BOX64_VERSION_FINAL_VAL=$(echo "${INPUT_BOX64_MATRIX_ENTRY}" | sed -n 's/.*"\([^"]*\)":"\([^"]*\)".*/\1/p')
          BOX64_DEB_URL_FINAL_VAL=$(echo "${INPUT_BOX64_MATRIX_ENTRY}" | sed -n 's/.*"\([^"]*\)":"\([^"]*\)".*/\2/p')
          echo "BOX64_VERSION_FINAL=${BOX64_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
          echo "BOX64_DEB_URL_FINAL=${BOX64_DEB_URL_FINAL_VAL}" >> "$GITHUB_ENV"
          echo "Using Box64 version: ${BOX64_VERSION_FINAL_VAL}"
      else
          echo "Warning: Could not parse INPUT_BOX64_MATRIX_ENTRY: ${INPUT_BOX64_MATRIX_ENTRY}"
      fi
    else
      echo "No Box64 entry for ARM, or entry is empty."
    fi
  fi
}

# Extracts the Debian codename from the base image tag
extract_debian_codename() {
  DEBIAN_CODENAME_VAL=$(echo "${INPUT_IMAGE_TAG_BASE}" | cut -d'-' -f1)
  echo "DEBIAN_CODENAME=${DEBIAN_CODENAME_VAL}" >> "$GITHUB_ENV"
  echo "Determined DEBIAN_CODENAME: ${DEBIAN_CODENAME_VAL}"
}

# Parses Wine/Proton configuration from the compatibility layer name
parse_compatibility_layer() {
  local compat_layer="${INPUT_COMPAT_LAYER_NAME}"
  COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL="" # for native or unhandled
  WINE_BRANCH_FINAL_VAL=""
  WINE_VERSION_FINAL_VAL=""
  PROTON_VERSION_FINAL_VAL="${PROTON_VERSION_GLOBAL}" # Default to global

  if [[ "${compat_layer}" =~ ^wine-(.+)-(.+)$ ]]; then
    WINE_BRANCH_FINAL_VAL="${BASH_REMATCH[1]}"
    WINE_VERSION_FINAL_VAL="${BASH_REMATCH[2]}"
    COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL="wine"
    echo "Parsed Wine: Branch=${WINE_BRANCH_FINAL_VAL}, Version=${WINE_VERSION_FINAL_VAL}"
  elif [[ "${compat_layer}" =~ ^proton-(.+)$ ]]; then
    PROTON_VERSION_FINAL_VAL="${BASH_REMATCH[1]}" # Layer specific overrides global
    COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL="proton"
    echo "Parsed Proton: Version=${PROTON_VERSION_FINAL_VAL}"
  elif [[ "${compat_layer}" == "native" ]]; then
    echo "Native compatibility layer, no Wine or Proton."
    # PROTON_VERSION_FINAL_VAL will remain from global but COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL is empty
  else
    echo "Unknown compatibility layer format: ${compat_layer}"
  fi

  echo "COMPAT_LAYER_TYPE_FOR_DOCKERFILE=${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" >> "$GITHUB_ENV"
  echo "WINE_BRANCH_FINAL=${WINE_BRANCH_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "WINE_VERSION_FINAL=${WINE_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "PROTON_VERSION_FINAL=${PROTON_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
}

# Builds various Docker tag versions
build_docker_tags() {
  # ===== Build Versioned Tag =====
  # Format: <image_base>[-compat_layer_details][-dev]-<arch>
  local tag_versioned_base="${INPUT_IMAGE_TAG_BASE}"
  if [[ "${INPUT_COMPAT_LAYER_NAME}" != "native" ]]; then
    tag_versioned_base="${tag_versioned_base}_${INPUT_COMPAT_LAYER_NAME}" # e.g., bookworm-slim_wine-staging-10.5
  fi
  if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then
    tag_versioned_base="${tag_versioned_base}_dev"
  fi
  FINAL_TAG_VERSIONED_ARCH_VAL="${tag_versioned_base}-${IMAGE_ARCHITECTURE_VAL}"
  echo "FINAL_TAG_VERSIONED_ARCH=${FINAL_TAG_VERSIONED_ARCH_VAL}" >> "$GITHUB_ENV"
  echo "Generated Versioned Tag (with arch): ${FINAL_TAG_VERSIONED_ARCH_VAL}"

  # ===== Build Codename Tag =====
  # Format: <debian_codename>[-wine-branch | -proton-version][-dev][_BOX86-ver_BOX64-ver]-<arch>
  local tag_codename_base="${DEBIAN_CODENAME_VAL}" # e.g. bookworm
  if [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "wine" ]]; then
    tag_codename_base="${tag_codename_base}-wine-${WINE_BRANCH_FINAL_VAL}"
  elif [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "proton" ]]; then
    tag_codename_base="${tag_codename_base}-proton-${PROTON_VERSION_FINAL_VAL}"
  fi
  # Add dev suffix if not on main branch
  if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then
    tag_codename_base="${tag_codename_base}_dev"
  fi
  # Add Box versions if applicable
  if [[ "${IMAGE_ARCHITECTURE_VAL}" == "arm64" && -n "${BOX86_VERSION_FINAL_VAL}" && -n "${BOX64_VERSION_FINAL_VAL}" ]]; then
    tag_codename_base="${tag_codename_base}_BOX86-${BOX86_VERSION_FINAL_VAL}_BOX64-${BOX64_VERSION_FINAL_VAL}"
  fi
  FINAL_TAG_CODENAME_ARCH_VAL="${tag_codename_base}-${IMAGE_ARCHITECTURE_VAL}"
  echo "FINAL_TAG_CODENAME_ARCH=${FINAL_TAG_CODENAME_ARCH_VAL}" >> "$GITHUB_ENV"
  echo "Generated Codename Tag (with arch): ${FINAL_TAG_CODENAME_ARCH_VAL}"

  # ===== Build Latest Tag (Arch Specific) =====
  # Only used for main branch & native builds
  HAS_LATEST_TAG_VAL="false"
  FINAL_TAG_LATEST_ARCH_VAL=""
  if [[ "${GITHUB_REF}" == "refs/heads/main" && "${INPUT_COMPAT_LAYER_NAME}" == "native" ]]; then
    FINAL_TAG_LATEST_ARCH_VAL="latest-${IMAGE_ARCHITECTURE_VAL}"
    HAS_LATEST_TAG_VAL="true"
    echo "Generated Latest Tag (with arch): ${FINAL_TAG_LATEST_ARCH_VAL}"
  fi
  echo "HAS_LATEST_TAG=${HAS_LATEST_TAG_VAL}" >> "$GITHUB_ENV"
  echo "FINAL_TAG_LATEST_ARCH=${FINAL_TAG_LATEST_ARCH_VAL}" >> "$GITHUB_ENV"
}

# Configures platform-specific settings for Docker build-args
configure_platform_settings() {
  local debugger_tool_val=""
  local app_command_prefix_val=""

  if [[ "${INPUT_PLATFORM}" == *"arm"* ]]; then # Could use IMAGE_ARCHITECTURE_VAL too
    debugger_tool_val="box86" # For debugging inside container if needed.
    app_command_prefix_val="box64 " # Prefix for running x86_64 apps on ARM via Box64
  fi

  # Further prefix with wine/proton if applicable
  if [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "wine" ]]; then
    app_command_prefix_val="wine ${app_command_prefix_val}"
  elif [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "proton" ]]; then
    # Assuming 'proton' is a command or script in the path within the Docker image
    app_command_prefix_val="proton ${app_command_prefix_val}"
  fi
  # Ensure trailing space is trimmed if prefix is not empty
  app_command_prefix_val=$(echo "${app_command_prefix_val}" | sed 's/ *$//')


  echo "DEBUGGER_TOOL=${debugger_tool_val}" >> "$GITHUB_ENV"
  echo "APP_COMMAND_PREFIX_FINAL=${app_command_prefix_val}" >> "$GITHUB_ENV"
  echo "Platform settings: DEBUGGER_TOOL=${debugger_tool_val}, APP_COMMAND_PREFIX_FINAL=${app_command_prefix_val}"
}

# Sets miscellaneous build metadata
set_build_metadata() {
  local build_date
  build_date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "BUILD_DATE_ISO=${build_date}" >> "$GITHUB_ENV"
  echo "Build date set to: ${build_date}"
}

# --- Main Script Logic ---
main() {
  echo "Starting Docker metadata preparation..."

  extract_architecture
  process_box_versions # Call after extract_architecture
  extract_debian_codename
  parse_compatibility_layer
  build_docker_tags # Call after arch, debian codename, compat layer, box versions are processed
  configure_platform_settings # Call after arch and compat layer are processed
  set_build_metadata

  echo "--- Generated Environment Variables for Docker Build ---"
  echo "IMAGE_ARCHITECTURE=${IMAGE_ARCHITECTURE_VAL}"
  echo "BOX86_VERSION_FINAL=${BOX86_VERSION_FINAL_VAL:-N/A}"
  echo "BOX86_DEB_URL_FINAL=${BOX86_DEB_URL_FINAL_VAL:-N/A}"
  echo "BOX64_VERSION_FINAL=${BOX64_VERSION_FINAL_VAL:-N/A}"
  echo "BOX64_DEB_URL_FINAL=${BOX64_DEB_URL_FINAL_VAL:-N/A}"
  echo "DEBIAN_CODENAME=${DEBIAN_CODENAME_VAL}"
  echo "COMPAT_LAYER_TYPE_FOR_DOCKERFILE=${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}"
  echo "WINE_BRANCH_FINAL=${WINE_BRANCH_FINAL_VAL:-N/A}"
  echo "WINE_VERSION_FINAL=${WINE_VERSION_FINAL_VAL:-N/A}"
  echo "PROTON_VERSION_FINAL=${PROTON_VERSION_FINAL_VAL}"
  echo "FINAL_TAG_VERSIONED_ARCH=${FINAL_TAG_VERSIONED_ARCH_VAL}"
  echo "FINAL_TAG_CODENAME_ARCH=${FINAL_TAG_CODENAME_ARCH_VAL}"
  echo "HAS_LATEST_TAG=${HAS_LATEST_TAG_VAL}"
  echo "FINAL_TAG_LATEST_ARCH=${FINAL_TAG_LATEST_ARCH_VAL:-N/A}"
  echo "DEBUGGER_TOOL=${DEBUGGER_TOOL_VAL:-N/A}"
  echo "APP_COMMAND_PREFIX_FINAL='${APP_COMMAND_PREFIX_FINAL:-N/A}'" # Note quotes for potential spaces
  echo "BUILD_DATE_ISO=${BUILD_DATE_ISO}"
  echo "----------------------------------------------------"
  echo "Docker metadata preparation complete."
}

# Execute main function
main
