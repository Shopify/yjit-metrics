#!/bin/bash -e

notify="$(realpath "${0%/*}/../slack_build_notifier.rb")"
{

  # Use Slack "mrkdwn" formatting.
  # https://api.slack.com/reference/surfaces/formatting
  echo "# Command failed"
  echo
  echo "\`$*\`"
  echo
  echo "_tail of ${LOG_FILE}_"
  echo
  echo '```'
  # Skip bash trace lines.
  grep -vE '^\++ ' "$LOG_FILE" | tail
  echo '```'

  # Pipe the above output to slack script to send to us.
  # Also record separate log file to make it easy to find.
} 2>&1 | "$notify" --title "$INSTANCE_NAME: Error" --image=fail - 2>&1 | tee "${LOG_FILE%.log}-notification.log"
