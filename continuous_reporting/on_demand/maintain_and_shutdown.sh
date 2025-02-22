#!/bin/bash -xe

# Do any periodic maintenance for machines that will live on
# then power down the instance when finished.

trap 'sudo shutdown' EXIT


log_dir="${LOG_FILE%/*}"

ts-expired () {
  local ts="$(cat "$1" 2>&-)" days="${2:-7}" now="$(date +%s)"
  local duration=$((86400 * days - 3600)) # days in seconds give or take an hour
  echo "Checking ($now - $ts) > $duration" >&2
  [[ -z "$ts" ]] || [[ $((now - ts)) -gt $duration ]]
}

update-ts () {
  date +%s > "$1"
}

# Run specified command only if it has been X days or more since the last run.
after-x-days () {
  local days="$1" cmd="$2"
  local ts_file="$log_dir/.ts-$cmd"
  if ts-expired "$ts_file" "$days"; then
    $cmd
    update-ts "$ts_file"
  else
    echo "Skipping $cmd"
  fi
}

apt-upgrade () {
  # apt-get
  # update: resynchronize the package index files
  # upgrade: install the newest versions of all packages currently installed
  sudo apt-get update -y && sudo apt-get upgrade -y
}

git-gc () {
  for i in ~/ym/*/.git; do
    GIT_DIR=$i git gc
  done
}

# Delete month-old log files.
find "$log_dir" -type f -not -newerct '30 days ago' -print -delete

# Re-enable rsyslog since logrotate expects it to be running.
sudo systemctl reenable rsyslog.service
# Trigger some services whose timers have been disabled.
sudo systemctl start fwupd-refresh.service logrotate.service

# Upgrade packages weekly.
after-x-days 7 apt-upgrade

# Compact git repos periodically.
# This always takes a long time to run
# but if run too frequently it won't produce sufficient gains for the time spent.
# Run it periodically to get a better ratio of "time spent" to "disk freed".
after-x-days 14 git-gc
