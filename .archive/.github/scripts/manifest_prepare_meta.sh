#!/bin/bash
set -e
set -o pipefail

# Purpose: Prepare metadata and tags for creating a multi-architecture manifest.
# This script focuses on generating the base tags for the manifest list,
# without the architecture suffix, as the manifest list itself is multi-arch.

# Input environment variables (expected from workflow env block):
# - INPUT_IMAGE_TAG_BASE (e.g., bookworm-20250407-slim)
# - INPUT_COMPAT_LAYER_NAME (e.g., wine-staging-10.5, proton-9.27, native)
# - GITHUB_REF (automatically available)
# - PROTON_VERSION_GLOBAL (global env var from workflow)
# The script also needs BOX86/BOX64 versions for arm64 specific tags.
# For manifest creation, we assume the Box versions are consistent for a given INPUT_IMAGE_TAG_BASE + INPUT_COMPAT_LAYER_NAME combination.
# We'll re-parse Box versions from the global MATRIX_BOX86/MATRIX_BOX64 env vars, taking the first one.
# This is a simplification. A more robust solution might involve passing the specific box versions
# used during the ARM64 build if they could vary per build matrix for the *same* manifest target.
# For now, assuming the first defined BOX versions are canonical for a manifest.
# Global env: MATRIX_BOX86, MATRIX_BOX64

# --- Global Variables ---
DEBIAN_CODENAME_VAL=""
COMPAT_LAYER_TYPE_FOR_MANIFEST_VAL=""
WINE_BRANCH_FOR_MANIFEST_VAL=""
PROTON_VERSION_FOR_MANIFEST_VAL="${PROTON_VERSION_GLOBAL}"
BOX86_VERSION_FOR_TAG_FINAL_VAL="" # Specifically for tagging manifests if ARM is involved
BOX64_VERSION_FOR_TAG_FINAL_VAL=""

# --- Function Definitions ---

extract_debian_codename_manifest() {
  DEBIAN_CODENAME_VAL=$(echo "${INPUT_IMAGE_TAG_BASE}" | cut -d'-' -f1)
  echo "DEBIAN_CODENAME_FOR_MANIFEST=${DEBIAN_CODENAME_VAL}" >> "$GITHUB_ENV" # For visibility
  echo "Manifest: Determined DEBIAN_CODENAME: ${DEBIAN_CODENAME_VAL}"
}

parse_compatibility_layer_manifest() {
  local compat_layer="${INPUT_COMPAT_LAYER_NAME}"
  # Reset for clarity
  COMPAT_LAYER_TYPE_FOR_MANIFEST_VAL=""
  WINE_BRANCH_FOR_MANIFEST_VAL=""
  # PROTON_VERSION_FOR_MANIFEST_VAL already defaulted to global

  if [[ "${compat_layer}" =~ ^wine-(.+)-(.+)$ ]]; then
    WINE_BRANCH_FOR_MANIFEST_VAL="${BASH_REMATCH[1]}"
    # Wine version detail (${BASH_REMATCH[2]}) is part of INPUT_COMPAT_LAYER_NAME for version tag
    COMPAT_LAYER_TYPE_FOR_MANIFEST_VAL="wine"
    echo "Manifest: Parsed Wine: Branch=${WINE_BRANCH_FOR_MANIFEST_VAL}"
  elif [[ "${compat_layer}" =~ ^proton-(.+)$ ]]; then
    PROTON_VERSION_FOR_MANIFEST_VAL="${BASH_REMATCH[1]}" # Layer specific overrides global
    COMPAT_LAYER_TYPE_FOR_MANIFEST_VAL="proton"
    echo "Manifest: Parsed Proton: Version=${PROTON_VERSION_FOR_MANIFEST_VAL}"
  elif [[ "${compat_layer}" == "native" ]]; then
    echo "Manifest: Native compatibility layer."
  else
    echo "Manifest: Unknown compatibility layer format: ${compat_layer}"
  fi
  # No direct GITHUB_ENV for these intermediate values, used in tag building
}

# This is a simplified way to get A box version for manifest tagging.
# Assumes the manifest is for a combination where box versions are consistent.
# Ideally, the build job for ARM would output the exact box versions used,
# and that output would be used to amend the manifest tag if it needs to be that specific.
# For now, we just use the first one defined globally if making an ARM related tag.
# This function is primarily for the CODENAME tag if it needs Box version identifiers.
# The VERSION tag for manifests usually doesn't include Box details as it points to arch-specific tags which do.
process_box_versions_for_manifest_tagging() {
    if [[ -n "${MATRIX_BOX86}" ]]; then # Check if MATRIX_BOX86 is set at all
        # Get the first line, then parse key
        local first_box86_entry
        first_box86_entry=$(echo "${MATRIX_BOX86}" | head -n1)
        if echo "${first_box86_entry}" | grep -qE '^([^=]+)='; then
            BOX86_VERSION_FOR_TAG_FINAL_VAL="${BASH_REMATCH[1]}"
            echo "BOX86_VERSION_FOR_TAG_FINAL=${BOX86_VERSION_FOR_TAG_FINAL_VAL}" >> "$GITHUB_ENV"
            echo "Manifest Tagging: Using Box86 version: ${BOX86_VERSION_FOR_TAG_FINAL_VAL}"
        fi
    fi
    if [[ -n "${MATRIX_BOX64}" ]]; then # Check if MATRIX_BOX64 is set at all
        local first_box64_entry
        first_box64_entry=$(echo "${MATRIX_BOX64}" | head -n1)
         if echo "${first_box64_entry}" | grep -qE '^([^=]+)='; then
            BOX64_VERSION_FOR_TAG_FINAL_VAL="${BASH_REMATCH[1]}"
            echo "BOX64_VERSION_FOR_TAG_FINAL=${BOX64_VERSION_FOR_TAG_FINAL_VAL}" >> "$GITHUB_ENV"
            echo "Manifest Tagging: Using Box64 version: ${BOX64_VERSION_FOR_TAG_FINAL_VAL}"
        fi
    fi
}


build_manifest_tags() {
  # ===== Base Version Tag (for manifest list, no arch) =====
  # Format: <image_base>[-compat_layer_details][-dev]
  local manifest_base_version_tag="${INPUT_IMAGE_TAG_BASE}"
  if [[ "${INPUT_COMPAT_LAYER_NAME}" != "native" ]]; then
    manifest_base_version_tag="${manifest_base_version_tag}_${INPUT_COMPAT_LAYER_NAME}"
  fi
  if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then
    manifest_base_version_tag="${manifest_base_version_tag}_dev"
  fi
  echo "MANIFEST_BASE_VERSION_TAG=${manifest_base_version_tag}" >> "$GITHUB_ENV" # Used by verify and create manifest scripts
  echo "MANIFEST_FINAL_VERSION_TAG=${manifest_base_version_tag}" >> "$GITHUB_ENV" # Actual tag for the manifest list
  echo "Manifest: Base Version Tag (no arch): ${manifest_base_version_tag}"


  # ===== Base Codename Tag (for manifest list, no arch, but might have Box for ARM context) =====
  # Format: <debian_codename>[-wine-branch | -proton-version][-dev][_BOX86-ver_BOX64-ver if relevant for how users find it]
  local manifest_base_codename_tag="${DEBIAN_CODENAME_VAL}"
  if [[ "${COMPAT_LAYER_TYPE_FOR_MANIFEST_VAL}" == "wine" ]]; then
    manifest_base_codename_tag="${manifest_base_codename_tag}-wine-${WINE_BRANCH_FOR_MANIFEST_VAL}"
  elif [[ "${COMPAT_LAYER_TYPE_FOR_MANIFEST_VAL}" == "proton" ]]; then
    manifest_base_codename_tag="${manifest_base_codename_tag}-proton-${PROTON_VERSION_FOR_MANIFEST_VAL}"
  fi
  if [[ "${GITHUB_REF}" != "refs/heads/main" ]]; then
    manifest_base_codename_tag="${manifest_base_codename_tag}_dev"
  fi

  # For codename manifest tags, if it's a type that would typically involve Box86/64 on arm64,
  # some users might expect Box version indicators in the multi-arch tag if they are significant.
  # This is debatable. The arch-specific tags HAVE the Box details.
  # Let's add them to the manifest codename tag if the compat layer is NOT native AND box versions are known.
  # This helps differentiate `bookworm-dev` (native) from `bookworm-wine-staging-dev_BOX...` (wine on arm64 implies box)
  if [[ "${INPUT_COMPAT_LAYER_NAME}" != "native" && -n "${BOX86_VERSION_FOR_TAG_FINAL_VAL}" && -n "${BOX64_VERSION_FOR_TAG_FINAL_VAL}" ]]; then
     manifest_base_codename_tag="${manifest_base_codename_tag}_BOX86-${BOX86_VERSION_FOR_TAG_FINAL_VAL}_BOX64-${BOX64_VERSION_FOR_TAG_FINAL_VAL}"
  fi

  echo "MANIFEST_BASE_CODENAME_TAG=${manifest_base_codename_tag}" >> "$GITHUB_ENV" # Used by verify and create manifest scripts
  echo "MANIFEST_FINAL_CODENAME_TAG=${manifest_base_codename_tag}" >> "$GITHUB_ENV" # Actual tag for the manifest list
  echo "Manifest: Base Codename Tag (no arch): ${manifest_base_codename_tag}"

  # ===== Latest Tag Flag (for manifest list) =====
  # The actual 'latest' tag is just 'latest' (no arch)
  local has_latest_for_manifest="false"
  if [[ "${GITHUB_REF}" == "refs/heads/main" && "${INPUT_COMPAT_LAYER_NAME}" == "native" ]]; then
    has_latest_for_manifest="true"
  fi
  echo "HAS_LATEST_TAG_FOR_MANIFEST=${has_latest_for_manifest}" >> "$GITHUB_ENV"
  echo "Manifest: Has Latest Tag Flag: ${has_latest_for_manifest}"
}

# --- Main Script Logic ---
main() {
  echo "Starting manifest metadata preparation..."

  extract_debian_codename_manifest
  parse_compatibility_layer_manifest
  process_box_versions_for_manifest_tagging # Call before building tags that might use box versions
  build_manifest_tags

  echo "--- Generated Environment Variables for Manifest Creation ---"
  echo "MANIFEST_BASE_VERSION_TAG (for composing arch specific): ${MANIFEST_BASE_VERSION_TAG}"
  echo "MANIFEST_FINAL_VERSION_TAG (for manifest list): ${MANIFEST_FINAL_VERSION_TAG}"
  echo "MANIFEST_BASE_CODENAME_TAG (for composing arch specific): ${MANIFEST_BASE_CODENAME_TAG}"
  echo "MANIFEST_FINAL_CODENAME_TAG (for manifest list): ${MANIFEST_FINAL_CODENAME_TAG}"
  echo "HAS_LATEST_TAG_FOR_MANIFEST: ${HAS_LATEST_TAG_FOR_MANIFEST}"
  echo "BOX86_VERSION_FOR_TAG_FINAL: ${BOX86_VERSION_FOR_TAG_FINAL_VAL:-N/A}"
  echo "BOX64_VERSION_FOR_TAG_FINAL: ${BOX64_VERSION_FOR_TAG_FINAL_VAL:-N/A}"
  echo "-------------------------------------------------------"
  echo "Manifest metadata preparation complete."
}

main
