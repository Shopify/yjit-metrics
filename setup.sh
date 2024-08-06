#!/bin/bash
# shellcheck disable=SC2317

set -e

setup-cpu () {
  # Keep commands simple so that they can be copied and pasted from this file with ease.

  echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
  echo 100 | sudo tee /sys/devices/system/cpu/intel_pstate/min_perf_pct
}

setup-packages () {
  sudo apt-get install -y \
    libsqlite3-dev \
    sqlite3 \
  && true
}

setup-all () {
  setup-cpu
  setup-packages
}

if [[ $(id -u) = 0 ]]; then
  echo "Don't run this as root, run it as a user that can sudo" >&2
  exit 1
fi

cmd="setup-$1"
if type -t "$cmd" >/dev/null; then
  set -x
  "$cmd"
  exit $?
fi

cat <<USAGE >&2
Usage: $0 action
Where action is: cpu, packages, or all
USAGE

exit 1
