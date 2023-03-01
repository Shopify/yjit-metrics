#!/bin/bash -l
# Note: may need a login shell, depending how chruby is installed.

set -e

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics

# No timestamp given, default to right now
ruby continuous_reporting/create_json_params_file.rb --full-rebuild=$FULL_REBUILD --bench-type=$BENCH_TYPE --yjit-metrics-name=$YJIT_METRICS_NAME --yjit-metrics-repo=$YJIT_METRICS_REPO --yjit-bench-name=$YJIT_BENCH_NAME --yjit-bench-repo=$YJIT_BENCH_REPO --cruby-name=$CRUBY_NAME --cruby-repo=$CRUBY_REPO --benchmark-data-dir=$BENCH_DATA_DIR

echo "Generated params successfully."
