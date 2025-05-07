#!/bin/bash
set -e
set -o pipefail

# Purpose: Set a build status output variable.

main() {
  echo "image-built=true" >> "$GITHUB_OUTPUT"
  echo "Build status set: image-built=true"
}

main
