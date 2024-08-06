#!/bin/bash
# shellcheck disable=SC2317

set -e

setup-cpu () {
  # Keep commands simple so that they can be copied and pasted from this file with ease.
  # TODO: Do we want to limit C-states in grub and rebuild the grub config?

  echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
  echo 100 | sudo tee /sys/devices/system/cpu/intel_pstate/min_perf_pct

  # hwp_dynamic_boost may not exist if disabled at boot time
  # (with `intel_pstate=no_hwp` in the kernel command line).
  if [[ -r /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost ]]; then
    echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost
  fi

  echo performance | sudo tee /sys/devices/system/cpu/cpu"$((`nproc` - 1))"/cpufreq/energy_performance_preference /sys/devices/system/cpu/cpu"$((`nproc` - 1))"/cpufreq/scaling_governor
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
