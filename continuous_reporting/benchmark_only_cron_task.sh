#!/bin/bash

# This script assumes that benchmark_prep_task has been run first to clean, rebuild and reinstall.

set -e

# I'm sure this shouldn't be necessary. But let's make sure env vars and chruby are set up, shall we?
. ~/.bashrc

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics
# This won't push the benchmarks to GitHub. And we tell it not to auto-file issues on the command line.
# So it shouldn't require GH tokens.
ruby continuous_reporting/benchmark_and_update.rb --no-gh-issue

echo "Completed benchmarking successfully."
