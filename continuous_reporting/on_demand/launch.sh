#!/bin/bash -ex

# Wrapper script to keep job coordinator code simple.
# Usage: $0 (benchmark|report)

action="$1"
case "$action" in
  benchmark|report)
    ;;
  *)
    echo "Unknown action: '$action'; Specify 'benchmark' or 'report'"
    exit 1
    ;;
esac

cr_dir="$(realpath "${0%/*}/..")"

# Put logs outside the repo so git commands don't clean them prematurely.
# Export this so subcommands can easily access it.
export LOG_FILE="$HOME/ym-logs/on-demand-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_FILE%/*}"

# Use the latest main and/or the requested repo/branch.
"$cr_dir"/gh_tasks/git_update_yjit_metrics_repo.sh 2>&1 | tee "$LOG_FILE"

echo Continuing in the background...

# Call separate script so that:
# - we use the latest logic from any files changed by the checkout
# - we detach from the current shell so that the job continues in the background
("$cr_dir"/on_demand/dispatch.sh "$@" >> "$LOG_FILE" 2>&1) & disown
