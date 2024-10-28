#!/bin/bash -ex

# This takes an argument of the action to perform (benchmark or report) and executes it.
# It is a separate executable from the launcher
# so that changes to this script can be easily tested in a branch.
# The launcher sets LOG_FILE and redirects all output from this script to it.

# Ensure ERR trap propagates to functions.
set -o errtrace

# If a command exits non-zero execute handle_error script.
trap "${0%/*}/handle_error.sh $*" ERR

# After any error is handlede it will call the EXIT trap.
# When we are all done we can just shutdown the instance.
# If anything went wrong the logs should be preserved on the instance for debugging.
trap "${0%/*}/maintain_and_shutdown.sh" EXIT

cr_dir="$(realpath "${0%/*}/..")"

do:benchmark () {
  # Some of the cpu settings do not persist across reboots and need to be set again.
  "$cr_dir"/../setup.sh cpu

  # This script needs BENCH_PARAMS env var.
  # It may exit non-zero but still produce some benchmarks
  # so preserve the exit status but proceed as if successful.
  "$cr_dir"/gh_tasks/run_benchmarks.sh || result=$?

  # Handle the slack notification explicitly for benchmark failures
  # and let the ERR trap handle everything else.
  if [[ $result -ne 0 ]]; then
    "$cr_dir"/slack_build_notifier.rb --properties STATUS=fail "$cr_dir"/data/*.json
  fi

  # Persist any result data if this was an official run.
  "$cr_dir"/gh_tasks/commit_benchmark_data.sh
}

do:report () {
  # Get results from most recent benchmarks.
  git -C ~/ym/raw-benchmark-data pull

  # Generate site with any new html files or new data.
  "$cr_dir"/gh_tasks/report_and_upload.sh
}

cmd="do:$1"; shift
"$cmd" "$@"
