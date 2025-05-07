#!/bin/bash
set -e
set -o pipefail

# Purpose: Test the built Docker image. Handles PRs vs. pushes and cross-architecture testing.

# Input environment variables (expected from workflow env block):
# - GITHUB_EVENT_NAME (automatically available)
# - INPUT_IMAGE_ARCH (architecture of the image being tested, e.g., amd64, arm64)
# - INPUT_TAG_TO_TEST (the specific arch-tag of the image, e.g., myimage:bookworm-amd64)
# - INPUT_REGISTRY_IMAGE (base registry image name, e.g., ghcr.io/user/image)

# --- Global Variables ---
RUNNER_ARCH_VAL=""
IMAGE_TO_TEST_CMD_VAL="" # Will be image ID for PRs, or full tag for pushes

# --- Function Definitions ---

determine_runner_architecture() {
  local arch
  arch=$(uname -m)
  if [[ "$arch" == "x86_64" ]]; then
    RUNNER_ARCH_VAL="amd64"
  elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    RUNNER_ARCH_VAL="arm64"
  else
    RUNNER_ARCH_VAL="$arch"
  fi
  echo "Runner architecture: ${RUNNER_ARCH_VAL}"
  echo "Image architecture: ${INPUT_IMAGE_ARCH}"
}

# Test logic for Pull Requests (uses locally built image ID)
test_for_pull_request() {
  echo "Testing locally built image for Pull Request..."
  # For local testing, use the loaded Docker image directly
  # Get the image ID from the build output (assumes it's the most recently built/loaded)
  # This might be fragile if multiple images are built by the docker/build-push-action without pushing
  # A more robust way would be if docker_build step in YAML outputted the specific image ID.
  # For now, taking the top one, assuming it's the one just built by buildx and loaded.
  local image_id
  image_id=$(docker images --format "{{.ID}}" "${INPUT_REGISTRY_IMAGE}" | head -n 1)

  if [[ -z "$image_id" ]]; then
    echo "::error::Could not find local image ID for ${INPUT_REGISTRY_IMAGE}. This indicates an issue with the image build or load process."
    exit 1
  fi
  IMAGE_TO_TEST_CMD_VAL="$image_id"
  echo "Using local image ID for testing: ${IMAGE_TO_TEST_CMD_VAL}"

  if [[ "$RUNNER_ARCH_VAL" != "$INPUT_IMAGE_ARCH" ]]; then
    echo "Skipping execution test for cross-architecture build (${INPUT_IMAGE_ARCH} on ${RUNNER_ARCH_VAL} runner) in PR mode."
    echo "Verification of build success is the primary goal here."
    echo "::notice::Image execution test skipped for cross-architecture in PR mode."
  else
    echo "Performing execution test on ${IMAGE_TO_TEST_CMD_VAL}..."
    docker run --rm "${IMAGE_TO_TEST_CMD_VAL}" bash -c "echo 'Local image execution test passed!'"
    echo "::notice::Local image execution test successfully completed!"
  fi
}

# Test logic for Pushes (uses pushed image from registry)
test_for_push() {
  echo "Testing pushed image from registry: ${INPUT_REGISTRY_IMAGE}:${INPUT_TAG_TO_TEST}"
  IMAGE_TO_TEST_CMD_VAL="${INPUT_REGISTRY_IMAGE}:${INPUT_TAG_TO_TEST}" # Use the full tag for pushes

  if [[ "$RUNNER_ARCH_VAL" != "$INPUT_IMAGE_ARCH" ]]; then
    echo "Cross-architecture scenario (${INPUT_IMAGE_ARCH} image on ${RUNNER_ARCH_VAL} runner)."
    echo "Verifying image manifest exists in the registry without attempting to run it directly."
    if docker buildx imagetools inspect "${IMAGE_TO_TEST_CMD_VAL}" &>/dev/null; then
      echo "::notice::Image ${IMAGE_TO_TEST_CMD_VAL} manifest verified in registry."
    else
      echo "::error::Image ${IMAGE_TO_TEST_CMD_VAL} manifest not found in registry after push."
      exit 1
    fi
  else
    echo "Same-architecture scenario. Pulling and running image ${IMAGE_TO_TEST_CMD_VAL}..."
    docker pull "${IMAGE_TO_TEST_CMD_VAL}"
    docker run --rm "${IMAGE_TO_TEST_CMD_VAL}" bash -c "echo 'Pushed image execution test passed!'"
    echo "::notice::Pushed image execution test successfully completed!"
  fi
}

# --- Main Script Logic ---
main() {
  echo "Starting Docker image test..."
  determine_runner_architecture

  if [[ "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
    test_for_pull_request
  else # Handles pushes to branches, tags, etc.
    test_for_push
  fi
  echo "Docker image test script finished."
}

main
