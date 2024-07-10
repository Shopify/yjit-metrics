#!/bin/bash -l

set -e
set -x

cd ~/ym/yjit-metrics

rm -f continuous_reporting/data/*intermediate*.json # These aren't kept
rm -f continuous_reporting/data/*crash_report*      # Nor are these
mv continuous_reporting/data/*.json ../ || echo ok  # If there's anything valuable here, move it to a higher level where it can be dealt with

# NOTE: git restore works even in detached-head state! So does git reset --hard, and it seems not to mess up
# other branches.

# Before we do various tasks, we want to get the latest yjit-metrics code and make sure we're on the right branch.

# As we start, we could be on a branch or in detached-head. We might have local changes (e.g. Gemfile.lock) or untracked
# files (e.g. from switching to/from detached-head states). We want to discard all that.
#
# At the end, we want to be at the latest version of $YJIT_METRICS_REPO/$YJIT_METRICS_NAME, where the name can be a branch
# name or a SHA.

# Set our remote to $YJIT_METRICS_REPO and make sure we have the latest version of it
git remote remove current_repo || echo ok # It's okay if the remove fails, e.g. if it doesn't exist
git remote add current_repo $YJIT_METRICS_REPO
git fetch current_repo

# Remove extraneous files - they can get in the way if we check out a branch
git clean -ffdx
git restore -SW .
git checkout current_repo/$YJIT_METRICS_NAME

# All this ref switching can leave cruft in the git database.
# Clean it to keep disk space under control.
git gc
