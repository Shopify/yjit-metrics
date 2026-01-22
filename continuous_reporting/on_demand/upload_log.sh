#!/bin/bash -e

logfile="$1"
url_file="$2"
[[ -n "$S3_LOGS_BUCKET" ]] || { echo "S3_LOGS_BUCKET not set" >&2; exit 1; }
[[ -f "$logfile" ]] || { echo "Log file not found: $logfile" >&2; exit 1; }

basename="${logfile##*/}"
s3_key="${INSTANCE_NAME:-unknown}/$basename"
s3_uri="s3://${S3_LOGS_BUCKET}/$s3_key"

aws s3 cp "$logfile" "$s3_uri" --content-type text/plain >&2

url=$(aws s3 presign "$s3_uri" --expires-in 604800)

if [[ -n "$url_file" ]]; then
  echo "$url" > "$url_file"
else
  echo "$url"
fi
