#!/bin/bash

set -e

# I'm sure this shouldn't be necessary. But let's make sure env vars and chruby are set up, shall we?
. ~/.bashrc

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
chruby 3.0.2

cd ~ubuntu/ym/yjit-metrics/
git pull
bundle
ruby continuous_reporting/benchmark_and_update.rb &> ~ubuntu/benchmark_ci_output.txt

echo "Completed successfully."
