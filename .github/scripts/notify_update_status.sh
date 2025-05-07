#!/bin/bash
set -e
set -o pipefail

# Purpose: Send out the final workflow status notification.

# Input environment variables (expected from workflow env block):
# - INPUT_WORKFLOW_STATUS
# - INPUT_WORKFLOW_MESSAGE

main() {
  echo "::notice::Workflow completed with overall status: [${INPUT_WORKFLOW_STATUS}]"
  echo "::notice::Summary: ${INPUT_WORKFLOW_MESSAGE}"

  # TODO: Add additional notification methods as needed:
  # Examples (these would require adding corresponding actions/steps in the YAML):
  # - Slack notification:
  #   echo "Sending Slack notification..."
  #   # (Call Slack action here, passing INPUT_WORKFLOW_STATUS and INPUT_WORKFLOW_MESSAGE)
  # - Email notification:
  #   echo "Sending Email notification..."
  #   # (Call Email action here)
  # - Teams notification:
  #   echo "Sending Teams notification..."
  #   # (Call Teams action here)

  if [[ "${INPUT_WORKFLOW_STATUS}" == "failure" ]]; then
    echo "::error::Workflow finished with failures. Please review the logs."
    # Consider exiting with 1 if you want the notification step itself to be marked as failed
    # although 'if: always()' on the job usually handles continuing.
    # exit 1
  fi
}

main
