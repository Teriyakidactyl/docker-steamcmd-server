#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Causes pipelines to fail on the first command that fails

# Purpose: Prepare Docker metadata, tags, labels, and build arguments for a single build matrix combination.
# Sets various environment variables for use in subsequent steps (docker metadata, docker build).

# Input environment variables (expected from workflow env block or 'with:' key):
# --- From Matrix/Workflow ---
# INPUT_PLATFORM (e.g., linux/amd64, linux/arm64)
# INPUT_IMAGE_TAG_BASE (e.g., bookworm-20250407-slim)
# INPUT_COMPAT_LAYER_NAME (e.g., wine-staging-10.5, proton-9.27, native)
# INPUT_BOX86_MATRIX_ENTRY (e.g., 0.3.9-d0aad67 - The key/version selected for Box86)
# INPUT_BOX64_MATRIX_ENTRY (e.g., 0.3.5-3542c88 - The key/version selected for Box64)
# --- Global Env ---
# MATRIX_BOX86 (Multi-line string: 'key=value\nkey=value')
# MATRIX_BOX64 (Multi-line string: 'key=value\nkey=value')
# GITHUB_REF (automatically available)
# PROTON_VERSION_GLOBAL
# WINE_ID
# WINE_TAG

# --- Check required inputs ---
: "${INPUT_PLATFORM:?Error: INPUT_PLATFORM is required.}"
: "${INPUT_IMAGE_TAG_BASE:?Error: INPUT_IMAGE_TAG_BASE is required.}"
: "${INPUT_COMPAT_LAYER_NAME:?Error: INPUT_COMPAT_LAYER_NAME is required.}"
: "${MATRIX_BOX86:?Error: MATRIX_BOX86 env var is required.}"
: "${MATRIX_BOX64:?Error: MATRIX_BOX64 env var is required.}"
# Allow BOX*_MATRIX_ENTRY to be empty for non-ARM builds
: "${INPUT_BOX86_MATRIX_ENTRY:=}"
: "${INPUT_BOX64_MATRIX_ENTRY:=}"

# --- Variable Declarations ---
# These will hold the final values determined by functions below
IMAGE_ARCHITECTURE_VAL=""
DEBIAN_CODENAME_VAL=""
COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL=""
WINE_BRANCH_FINAL_VAL=""
WINE_VERSION_FINAL_VAL=""
PROTON_VERSION_FINAL_VAL=""
BOX86_VERSION_FINAL_VAL="N/A" # Default to N/A
BOX86_DEB_URL_FINAL_VAL="N/A" # Default to N/A
BOX64_VERSION_FINAL_VAL="N/A" # Default to N/A
BOX64_DEB_URL_FINAL_VAL="N/A" # Default to N/A
FINAL_TAG_VERSIONED_ARCH_VAL=""
FINAL_TAG_CODENAME_ARCH_VAL=""
HAS_LATEST_TAG_VAL="false"
FINAL_TAG_LATEST_ARCH_VAL=""
DEBUGGER_TOOL_VAL=""
APP_COMMAND_PREFIX_FINAL_VAL=""
BUILD_DATE_ISO_VAL=""


# --- Function Definitions ---

# Extracts the architecture (amd64, arm64) from the platform string
extract_architecture() {
  IMAGE_ARCHITECTURE_VAL=$(echo "${INPUT_PLATFORM}" | cut -d'/' -f2)
  echo "Determined IMAGE_ARCHITECTURE: ${IMAGE_ARCHITECTURE_VAL}"
}

# Processes Box86/Box64 versions if on ARM architecture using grep/parameter expansion
process_box_versions() {
  # Reset defaults inside function scope in case it's called multiple times (though not expected here)
  BOX86_VERSION_FINAL_VAL="N/A"
  BOX86_DEB_URL_FINAL_VAL="N/A"
  BOX64_VERSION_FINAL_VAL="N/A"
  BOX64_DEB_URL_FINAL_VAL="N/A"

  if [[ "${IMAGE_ARCHITECTURE_VAL}" == "arm64" ]]; then
    echo "Processing Box versions for arm64..."

    # --- Process Box86 ---
    local target_box86_key="$INPUT_BOX86_MATRIX_ENTRY"
    echo "Target Box86 key: $target_box86_key"
    if [[ -n "$target_box86_key" ]]; then
      # grep for the line starting with the key followed by '='
      # Use '|| true' to prevent script exit if grep finds nothing
      local matching_line_86
      matching_line_86=$(echo "$MATRIX_BOX86" | grep "^${target_box86_key}=" || true)

      if [[ -n "$matching_line_86" ]]; then
        # Use bash parameter expansion to remove everything up to and including the first '='
        BOX86_VERSION_FINAL_VAL="$target_box86_key"
        BOX86_DEB_URL_FINAL_VAL="${matching_line_86#*=}"
        echo "Found Box86 URL: ${BOX86_DEB_URL_FINAL_VAL}"
      else
        echo "::warning::BOX86 entry key '$target_box86_key' not found in MATRIX_BOX86."
      fi
    else
      echo "No INPUT_BOX86_MATRIX_ENTRY provided or it is empty."
    fi

    # --- Process Box64 ---
    local target_box64_key="$INPUT_BOX64_MATRIX_ENTRY"
    echo "Target Box64 key: $target_box64_key"
     if [[ -n "$target_box64_key" ]]; then
        local matching_line_64
        matching_line_64=$(echo "$MATRIX_BOX64" | grep "^${target_box64_key}=" || true)

        if [[ -n "$matching_line_64" ]]; then
            BOX64_VERSION_FINAL_VAL="$target_box64_key"
            BOX64_DEB_URL_FINAL_VAL="${matching_line_64#*=}"
            echo "Found Box64 URL: ${BOX64_DEB_URL_FINAL_VAL}"
        else
            echo "::warning::BOX64 entry key '$target_box64_key' not found in MATRIX_BOX64."
        fi
     else
        echo "No INPUT_BOX64_MATRIX_ENTRY provided or it is empty."
    fi
  else
      echo "Not an ARM64 architecture, skipping Box version processing."
  fi

  # Set GITHUB_ENV vars based on the final determined values
  echo "BOX86_VERSION_FINAL=${BOX86_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "BOX86_DEB_URL_FINAL=${BOX86_DEB_URL_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "BOX64_VERSION_FINAL=${BOX64_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "BOX64_DEB_URL_FINAL=${BOX64_DEB_URL_FINAL_VAL}" >> "$GITHUB_ENV"
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
  # Reset defaults
  COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL=""
  WINE_BRANCH_FINAL_VAL=""
  WINE_VERSION_FINAL_VAL=""
  PROTON_VERSION_FINAL_VAL="${PROTON_VERSION_GLOBAL:-}" # Default to global if set, else empty

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
    # PROTON_VERSION_FINAL_VAL remains default, COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL remains empty
  else
    echo "::warning::Unknown compatibility layer format: ${compat_layer}"
  fi

  echo "COMPAT_LAYER_TYPE_FOR_DOCKERFILE=${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" >> "$GITHUB_ENV"
  echo "WINE_BRANCH_FINAL=${WINE_BRANCH_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "WINE_VERSION_FINAL=${WINE_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "PROTON_VERSION_FINAL=${PROTON_VERSION_FINAL_VAL}" >> "$GITHUB_ENV"
}

# Builds various Docker tag versions
build_docker_tags() {
  # ===== Build Versioned Tag =====
  local tag_versioned_base="${INPUT_IMAGE_TAG_BASE}"
  if [[ "${INPUT_COMPAT_LAYER_NAME}" != "native" ]]; then
    tag_versioned_base="${tag_versioned_base}_${INPUT_COMPAT_LAYER_NAME}"
  fi
  if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then
    tag_versioned_base="${tag_versioned_base}_dev"
  fi
  FINAL_TAG_VERSIONED_ARCH_VAL="${tag_versioned_base}-${IMAGE_ARCHITECTURE_VAL}"
  echo "FINAL_TAG_VERSIONED_ARCH=${FINAL_TAG_VERSIONED_ARCH_VAL}" >> "$GITHUB_ENV"
  echo "Generated Versioned Tag (with arch): ${FINAL_TAG_VERSIONED_ARCH_VAL}"

  # ===== Build Codename Tag =====
  local tag_codename_base="${DEBIAN_CODENAME_VAL}"
  if [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "wine" ]]; then
    tag_codename_base="${tag_codename_base}-wine-${WINE_BRANCH_FINAL_VAL}"
  elif [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "proton" ]]; then
    tag_codename_base="${tag_codename_base}-proton-${PROTON_VERSION_FINAL_VAL}"
  fi
  if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then
    tag_codename_base="${tag_codename_base}_dev"
  fi
  # Add Box versions if applicable (check final vals set previously)
  if [[ "${IMAGE_ARCHITECTURE_VAL}" == "arm64" && "${BOX86_VERSION_FINAL_VAL}" != "N/A" && "${BOX64_VERSION_FINAL_VAL}" != "N/A" ]]; then
    tag_codename_base="${tag_codename_base}_BOX86-${BOX86_VERSION_FINAL_VAL}_BOX64-${BOX64_VERSION_FINAL_VAL}"
  fi
  FINAL_TAG_CODENAME_ARCH_VAL="${tag_codename_base}-${IMAGE_ARCHITECTURE_VAL}"
  echo "FINAL_TAG_CODENAME_ARCH=${FINAL_TAG_CODENAME_ARCH_VAL}" >> "$GITHUB_ENV"
  echo "Generated Codename Tag (with arch): ${FINAL_TAG_CODENAME_ARCH_VAL}"

  # ===== Build Latest Tag (Arch Specific) =====
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
  DEBUGGER_TOOL_VAL=""
  APP_COMMAND_PREFIX_FINAL_VAL="" # Renamed internal var

  if [[ "${INPUT_PLATFORM}" == *"arm"* ]]; then
    DEBUGGER_TOOL_VAL="box86"
    APP_COMMAND_PREFIX_FINAL_VAL="box64 " # Note trailing space
  fi

  if [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "wine" ]]; then
    APP_COMMAND_PREFIX_FINAL_VAL="wine ${APP_COMMAND_PREFIX_FINAL_VAL}"
  elif [[ "${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" == "proton" ]]; then
    APP_COMMAND_PREFIX_FINAL_VAL="proton run ${APP_COMMAND_PREFIX_FINAL_VAL}" # Assuming proton needs 'run'
  fi

  # Trim trailing space if present
  APP_COMMAND_PREFIX_FINAL_VAL=$(echo "${APP_COMMAND_PREFIX_FINAL_VAL}" | sed 's/ *$//')

  echo "DEBUGGER_TOOL=${DEBUGGER_TOOL_VAL}" >> "$GITHUB_ENV"
  echo "APP_COMMAND_PREFIX_FINAL=${APP_COMMAND_PREFIX_FINAL_VAL}" >> "$GITHUB_ENV"
  echo "Platform settings: DEBUGGER_TOOL=${DEBUGGER_TOOL_VAL:-N/A}, APP_COMMAND_PREFIX_FINAL=${APP_COMMAND_PREFIX_FINAL_VAL:-N/A}"
}


# Sets miscellaneous build metadata
set_build_metadata() {
  BUILD_DATE_ISO_VAL=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "BUILD_DATE_ISO=${BUILD_DATE_ISO_VAL}" >> "$GITHUB_ENV"
  echo "Build date set to: ${BUILD_DATE_ISO_VAL}"
}

# --- Main Script Logic ---
main() {
  echo "Starting Docker metadata preparation..."

  extract_architecture
  process_box_versions # Depends on IMAGE_ARCHITECTURE_VAL
  extract_debian_codename
  parse_compatibility_layer # Sets COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL etc.
  configure_platform_settings # Depends on IMAGE_ARCHITECTURE_VAL, COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL
  build_docker_tags # Depends on many previous values including Box final versions
  set_build_metadata

  # === Final Summary Output ===
  # Use :-N/A parameter expansion to provide default if var is unset or null
  echo "--- Generated Environment Variables for Docker Build ---"
  echo "IMAGE_ARCHITECTURE=${IMAGE_ARCHITECTURE_VAL:-N/A}"
  echo "BOX86_VERSION_FINAL=${BOX86_VERSION_FINAL_VAL:-N/A}"
  echo "BOX86_DEB_URL_FINAL=${BOX86_DEB_URL_FINAL_VAL:-N/A}"
  echo "BOX64_VERSION_FINAL=${BOX64_VERSION_FINAL_VAL:-N/A}"
  echo "BOX64_DEB_URL_FINAL=${BOX64_DEB_URL_FINAL_VAL:-N/A}"
  echo "DEBIAN_CODENAME=${DEBIAN_CODENAME_VAL:-N/A}"
  echo "COMPAT_LAYER_TYPE_FOR_DOCKERFILE=${COMPAT_LAYER_TYPE_FOR_DOCKERFILE_VAL}" # Can be empty
  echo "WINE_BRANCH_FINAL=${WINE_BRANCH_FINAL_VAL:-N/A}" # Can be empty
  echo "WINE_VERSION_FINAL=${WINE_VERSION_FINAL_VAL:-N/A}" # Can be empty
  echo "PROTON_VERSION_FINAL=${PROTON_VERSION_FINAL_VAL:-N/A}"
  echo "FINAL_TAG_VERSIONED_ARCH=${FINAL_TAG_VERSIONED_ARCH_VAL:-N/A}"
  echo "FINAL_TAG_CODENAME_ARCH=${FINAL_TAG_CODENAME_ARCH_VAL:-N/A}"
  echo "HAS_LATEST_TAG=${HAS_LATEST_TAG_VAL:-false}"
  echo "FINAL_TAG_LATEST_ARCH=${FINAL_TAG_LATEST_ARCH_VAL:-N/A}" # Can be empty
  echo "DEBUGGER_TOOL=${DEBUGGER_TOOL_VAL:-N/A}" # Can be empty
  echo "APP_COMMAND_PREFIX_FINAL=${APP_COMMAND_PREFIX_FINAL_VAL:-N/A}" # Can be empty
  echo "BUILD_DATE_ISO=${BUILD_DATE_ISO_VAL:-N/A}"
  echo "----------------------------------------------------"
  echo "Docker metadata preparation complete."
}

# Execute main function
main