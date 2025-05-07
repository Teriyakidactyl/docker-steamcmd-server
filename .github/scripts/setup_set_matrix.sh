#!/bin/bash
set -e
set -o pipefail

# Purpose: Process multiline environment variables from workflow into JSON arrays
#          and JSON objects into specific JSON array structures for use in
#          GitHub Actions matrix strategies.

# Input environment variables (expected from workflow env block):
# - INPUT_MATRIX_IMAGES
# - INPUT_MATRIX_COMPAT_LAYERS
# - INPUT_MATRIX_PLATFORMS
# - INPUT_MATRIX_BOX86 (a JSON string, e.g., '{"version1":"url1","version2":"url2"}')
# - INPUT_MATRIX_BOX64 (a JSON string, e.g., '{"version1":"url1","version2":"url2"}')

main() {
  # Process the multiline env vars into JSON arrays for matrix strategy
  # Remove empty lines, add quotes, convert to JSON array
  echo "image-tags=$(echo "${INPUT_MATRIX_IMAGES}" | grep -v '^$' | awk '{print "\""$0"\""}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"
  echo "compat-layers=$(echo "${INPUT_MATRIX_COMPAT_LAYERS}" | grep -v '^$' | awk '{print "\""$0"\""}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"
  echo "platforms=$(echo "${INPUT_MATRIX_PLATFORMS}" | grep -v '^$' | awk '{print "\""$0"\""}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"

  # For Box86/Box64, the input is a JSON object string.
  # Convert it to a JSON array of objects, where each object is { "version": "key", "url": "value" }.
  # This structure is suitable for 'Pass the whole entry' if matrix.box86_matrix_entry is used.
  if command -v jq &> /dev/null; then
    box86_versions_array=$(echo "${INPUT_MATRIX_BOX86}" | jq -c 'to_entries | map({version: .key, url: .value})')
    echo "box86-versions=${box86_versions_array}" >> "$GITHUB_OUTPUT"

    box64_versions_array=$(echo "${INPUT_MATRIX_BOX64}" | jq -c 'to_entries | map({version: .key, url: .value})')
    echo "box64-versions=${box64_versions_array}" >> "$GITHUB_OUTPUT"
  else
    echo "::error::jq is not installed. Cannot process INPUT_MATRIX_BOX86 and INPUT_MATRIX_BOX64."
    exit 1
  fi

  echo "Matrix configurations processed."
}

main
