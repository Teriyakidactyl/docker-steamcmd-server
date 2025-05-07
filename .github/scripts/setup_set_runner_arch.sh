#!/bin/bash
set -e
set -o pipefail

# Purpose: Determine the architecture of the GitHub runner and output it.

main() {
  # Determine the architecture of the GitHub runner
  local runner_hw_arch
  runner_hw_arch=$(uname -m)
  local output_arch

  if [[ "$runner_hw_arch" == "x86_64" ]]; then
    output_arch="amd64"
  elif [[ "$runner_hw_arch" == "aarch64" || "$runner_hw_arch" == "arm64" ]]; then
    output_arch="arm64"
  else
    output_arch="$runner_hw_arch" # Should not happen for standard GitHub runners
  fi

  echo "arch=${output_arch}" >> "$GITHUB_OUTPUT"
  echo "Runner hardware architecture: $runner_hw_arch, mapped to: $output_arch"
}

main
