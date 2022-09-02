#!/bin/bash

# This script assumes that benchmark_prep_task has been run first to clean, rebuild and reinstall.

set -e

# I'm sure this shouldn't be necessary. But let's make sure env vars and chruby are set up, shall we?
. ~/.bashrc

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics
# If we uncomment this, it'll run reporting but not benchmarking. That will file GH issues for perf drops.
# ruby continuous_reporting/benchmark_and_update.rb -b none

# This should be a no-op run since we generated reports locally along with benchmarks.
# But just in case, we'll tell it to do reporting. We also push results to GitHub.
# If you want to *require* this to be a no-op run, pass the --prevent-regenerate flag.
ruby continuous_reporting/generate_and_upload_reports.rb

# Now we'll verify that we're not regenerating results when we shouldn't.
# To do that we'll tell generate_and_upload not to do Git checkins,
# and to fail if we try to generate any reports. The previous run
# was *supposed* to generate everything that needed it.
# If this fails, we're probably not reporting deterministically. No output
# should just change run-to-run.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push --prevent-regenerate

echo "Completed successfully."
