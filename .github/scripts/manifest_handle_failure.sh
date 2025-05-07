#!/bin/bash
set -e
set -o pipefail

# Purpose: Output error message on manifest creation failure.

main() {
  echo "::error::Failed to create one or more multi-architecture manifests."
  echo "::error::Check if all architecture-specific images were successfully built, pushed, and verified."
  echo "::error::Review the logs from 'Create and push multi-architecture manifests' step for details."
}

main
