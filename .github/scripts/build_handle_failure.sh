#!/bin/bash
set -e # Not strictly needed as it's an error handler, but good practice
set -o pipefail

# Purpose: Output error message on build failure.

# Input environment variables (expected from workflow env block):
# - INPUT_MATRIX_IMAGE
# - INPUT_MATRIX_COMPAT_LAYER
# - INPUT_MATRIX_PLATFORM

main() {
  echo "::error::Docker build failed for image [${INPUT_MATRIX_IMAGE}] with compatibility layer [${INPUT_MATRIX_COMPAT_LAYER}] on platform [${INPUT_MATRIX_PLATFORM}]"
  echo "::error::Check the logs above in the 'Build and push Docker image' step for more details on the failure."
}

main
