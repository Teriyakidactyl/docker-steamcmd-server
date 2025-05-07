#!/bin/bash
set -e
set -o pipefail

# Purpose: Create and push multi-architecture "fat" manifests.

# Input environment variables (expected from workflow env block):
# - INPUT_REGISTRY_IMAGE
# - INPUT_MANIFEST_VERSION_TAG (e.g., bookworm-slim_wine-staging-10.5_dev - this is the target manifest tag)
# - INPUT_MANIFEST_CODENAME_TAG (e.g., bookworm-wine-staging_dev[_BOX...])
# - INPUT_HAS_LATEST_TAG_FOR_MANIFEST ("true" or "false")
#
# - INPUT_BASE_VERSION_TAG_NO_ARCH (used to find -amd64, -arm64 suffixed images)
# - INPUT_BASE_CODENAME_TAG_NO_ARCH (used to find -amd64, -arm64 suffixed images, arm64 version has box)
#
# - INPUT_BOX86_VERSION_FOR_TAG (used to construct arm64 codename tag if needed for latest)
# - INPUT_BOX64_VERSION_FOR_TAG (used to construct arm64 codename tag if needed for latest)

# --- Function Definitions ---

create_manifest_list() {
  local manifest_list_tag="$1" # The final tag for the multi-arch manifest list
  local base_tag_for_finding_arch_imgs="$2" # Base tag used to find arch-specific images
  local base_codename_tag_for_finding_arch_imgs_if_different="$3" # Optional: if codename arch tags are different

  local amd64_image_tag=""
  local arm64_image_tag=""

  if [[ -n "$base_codename_tag_for_finding_arch_imgs_if_different" && "$manifest_list_tag" == "$INPUT_MANIFEST_CODENAME_TAG" ]]; then
    # Handling CODENAME manifest specifically
    local codename_base_amd64_no_box=$(echo "${base_codename_tag_for_finding_arch_imgs_if_different}" | sed -E 's/_BOX86-[^_]+_BOX64-[^_]+//')
    amd64_image_tag="${INPUT_REGISTRY_IMAGE}:${codename_base_amd64_no_box}-amd64"
    arm64_image_tag="${INPUT_REGISTRY_IMAGE}:${base_codename_tag_for_finding_arch_imgs_if_different}-arm64" #This base has box
  else
    # Handling VERSIONED manifest (and LATEST, which is based on native versioned)
    amd64_image_tag="${INPUT_REGISTRY_IMAGE}:${base_tag_for_finding_arch_imgs}-amd64"
    arm64_image_tag="${INPUT_REGISTRY_IMAGE}:${base_tag_for_finding_arch_imgs}-arm64"
  fi

  echo "Creating manifest list: ${INPUT_REGISTRY_IMAGE}:${manifest_list_tag}"
  echo "  Using amd64 image: ${amd64_image_tag}"
  echo "  Using arm64 image: ${arm64_image_tag}"

  docker buildx imagetools create --tag "${INPUT_REGISTRY_IMAGE}:${manifest_list_tag}" \
    "${amd64_image_tag}" \
    "${arm64_image_tag}"
  echo "::notice::Successfully created manifest: ${INPUT_REGISTRY_IMAGE}:${manifest_list_tag}"
}

# --- Main Script Logic ---
main() {
  echo "Starting creation of multi-architecture manifests..."

  # Create version tag fat manifest
  if [[ -n "${INPUT_MANIFEST_VERSION_TAG}" ]]; then
    create_manifest_list "${INPUT_MANIFEST_VERSION_TAG}" "${INPUT_BASE_VERSION_TAG_NO_ARCH}"
  else
    echo "Skipping version manifest creation as INPUT_MANIFEST_VERSION_TAG is not set."
  fi

  # Create codename tag fat manifest
  if [[ -n "${INPUT_MANIFEST_CODENAME_TAG}" ]]; then
    create_manifest_list "${INPUT_MANIFEST_CODENAME_TAG}" "${INPUT_BASE_CODENAME_TAG_NO_ARCH}" "${INPUT_BASE_CODENAME_TAG_NO_ARCH}" # Pass it twice to trigger codename logic
  else
    echo "Skipping codename manifest creation as INPUT_MANIFEST_CODENAME_TAG is not set."
  fi

  # Create "latest" tag if applicable
  if [[ "${INPUT_HAS_LATEST_TAG_FOR_MANIFEST}" == "true" ]]; then
    echo "Creating 'latest' multi-architecture manifest..."
    # 'latest' is based on the native version.
    # The base tag for finding arch-specific 'latest' images is 'latest' itself (e.g., ghcr.io/user/image:latest-amd64)
    # The manifest_prepare_meta.sh step sets HAS_LATEST_TAG_FOR_MANIFEST = true if native build on main.
    # The build_prepare_docker_meta.sh sets FINAL_TAG_LATEST_ARCH = latest-amd64 / latest-arm64.
    # So we need to reference these specific latest-arch tags.
    
    local latest_amd64_image="${INPUT_REGISTRY_IMAGE}:latest-amd64"
    local latest_arm64_image="${INPUT_REGISTRY_IMAGE}:latest-arm64"

    echo "  Using amd64 image: ${latest_amd64_image}"
    echo "  Using arm64 image: ${latest_arm64_image}"

    # First, ensure these arch-specific 'latest' tags actually exist (should have been verified by manifest_verify_images.sh if it was more generic)
    # For safety, re-verify here.
    if ! docker buildx imagetools inspect "${latest_amd64_image}" >/dev/null 2>&1; then
        echo "::error::latest-amd64 image (${latest_amd64_image}) not found. Cannot create 'latest' manifest."
        exit 1
    fi
     if ! docker buildx imagetools inspect "${latest_arm64_image}" >/dev/null 2>&1; then
        echo "::error::latest-arm64 image (${latest_arm64_image}) not found. Cannot create 'latest' manifest."
        exit 1
    fi

    docker buildx imagetools create --tag "${INPUT_REGISTRY_IMAGE}:latest" \
      "${latest_amd64_image}" \
      "${latest_arm64_image}"
    echo "::notice::Successfully created 'latest' multi-architecture manifest."
  else
    echo "Skipping 'latest' manifest creation as INPUT_HAS_LATEST_TAG_FOR_MANIFEST is not 'true'."
  fi

  echo "Multi-architecture manifest creation complete."
}

main
