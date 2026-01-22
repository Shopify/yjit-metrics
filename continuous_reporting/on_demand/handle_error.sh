#!/bin/bash -e

notify="$(realpath "${0%/*}/../slack_build_notifier.rb")"

log_url=""
log_url_file="${LOG_FILE%.log}-s3-url.txt"
if [[ -n "$S3_LOGS_BUCKET" ]]; then
  "${0%/*}/upload_log.sh" "$LOG_FILE" "$log_url_file" || true
  [[ -f "$log_url_file" ]] && log_url=$(<"$log_url_file")
fi

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
  if [[ -n "$log_url" ]]; then
    echo
    echo "<$log_url|View full log>"
  fi

  # Pipe the above output to slack script to send to us.
  # Also record separate log file to make it easy to find.
} 2>&1 | "$notify" --title "$INSTANCE_NAME: Error" --image=fail - 2>&1 | tee "${LOG_FILE%.log}-notification.log"
