#!/bin/bash
set -e
set -o pipefail

# Purpose: Process multiline environment variables from workflow into JSON arrays
#          for use in GitHub Actions matrix strategies.

# Input environment variables (expected from workflow env block):
# - INPUT_MATRIX_IMAGES
# - INPUT_MATRIX_COMPAT_LAYERS
# - INPUT_MATRIX_PLATFORMS
# - INPUT_MATRIX_BOX86
# - INPUT_MATRIX_BOX64

echo "TESTME"

main() {
  # Process the multiline env vars into JSON arrays for matrix strategy
  # Remove empty lines, add quotes, convert to JSON array
  echo "image-tags=$(echo "${INPUT_MATRIX_IMAGES}" | grep -v '^$' | awk '{print "\""$0"\""}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"
  echo "compat-layers=$(echo "${INPUT_MATRIX_COMPAT_LAYERS}" | grep -v '^$' | awk '{print "\""$0"\""}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"
  echo "platforms=$(echo "${INPUT_MATRIX_PLATFORMS}" | grep -v '^$' | awk '{print "\""$0"\""}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"

  # For Box86/Box64, the structure is key=value, so we convert to an array of JSON objects
  # Example input: version1=url1\nversion2=url2
  # Example output: [{"version1":"url1"},{"version2":"url2"}]
  echo "box86-versions=$(echo "${INPUT_MATRIX_BOX86}" | grep -v '^$' | awk -F'=' '{print "{\""$1"\":\""$2"\"}"}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"
  echo "box64-versions=$(echo "${INPUT_MATRIX_BOX64}" | grep -v '^$' | awk -F'=' '{print "{\""$1"\":\""$2"\"}"}' | paste -sd, | awk '{print "["$0"]"}')" >> "$GITHUB_OUTPUT"

  echo "Matrix configurations processed."
}

main
