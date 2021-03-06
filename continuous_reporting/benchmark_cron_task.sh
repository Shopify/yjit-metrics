#!/bin/bash

# This script assumes that benchmark_prep_task has been run first to clean, rebuild and reinstall.

set -e

# I'm sure this shouldn't be necessary. But let's make sure env vars and chruby are set up, shall we?
. ~/.bashrc

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics
ruby continuous_reporting/benchmark_and_update.rb

# Now we'll verify that we're not regenerating results when we shouldn't.
# To do that we'll tell generate_and_upload not to do Git checkins,
# and to fail if we try to generate any reports. The previous run
# was *supposed* to generate everything that needed it.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push --prevent-regenerate

echo "Completed successfully."
