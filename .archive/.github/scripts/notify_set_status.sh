#!/bin/bash
set -e
set -o pipefail

# Purpose: Determine the overall workflow status for notification.

# Input environment variables (expected from workflow env block):
# - NEEDS_CREATE_MANIFEST_RESULT
# - NEEDS_BUILD_RESULT

main() {
  local final_status="success"
  local final_message="Docker images successfully built and pushed, manifests created."

  # Check build result first, as manifest depends on it.
  if [[ "${NEEDS_BUILD_RESULT}" == "failure" ]]; then
    final_status="failure"
    final_message="Workflow failed during the build phase. Some Docker images may not have been built or pushed."
  elif [[ "${NEEDS_BUILD_RESULT}" == "cancelled" ]]; then
    final_status="cancelled"
    final_message="Workflow was cancelled during the build phase."
  else # Build was success or skipped (e.g. if only manifest failed on a re-run)
      # Now check manifest result
      if [[ "${NEEDS_CREATE_MANIFEST_RESULT}" == "failure" ]]; then
        final_status="failure"
        final_message="Workflow failed during the manifest creation phase. Images might be built, but manifests are missing or incomplete."
      elif [[ "${NEEDS_CREATE_MANIFEST_RESULT}" == "cancelled" ]]; then
        final_status="cancelled"
        final_message="Workflow was cancelled during the manifest creation phase."
      elif [[ "${NEEDS_CREATE_MANIFEST_RESULT}" == "skipped" ]]; then
        # This can happen if it's a PR, or if build job didn't produce output for manifest to run.
        # If build was successful, but manifest skipped (e.g. PR), it's not a failure.
        if [[ "${NEEDS_BUILD_RESULT}" == "success" && "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
            final_status="success" # For PR, build success is sufficient.
            final_message="Docker images successfully built (manifest creation skipped for PR)."
        elif [[ "${NEEDS_BUILD_RESULT}" == "success" ]]; then
             final_status="warning" # Or some other status indicating manifest was skipped not due to PR
             final_message="Docker images built, but manifest creation was skipped. Review conditions."
        else
            final_status="failure" # Build was not success, and manifest skipped - likely due to build issue
            final_message="Workflow encountered issues: build status '${NEEDS_BUILD_RESULT}', manifest creation skipped."
        fi
      fi
  fi


  echo "status=${final_status}" >> "$GITHUB_OUTPUT"
  echo "message=${final_message}" >> "$GITHUB_OUTPUT"

  echo "Notification status determined: ${final_status} - ${final_message}"
}

main
