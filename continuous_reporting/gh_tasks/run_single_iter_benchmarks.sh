#!/bin/bash -l
# Note: may need a login shell, depending how chruby is installed.

# This script assumes that Rubies have already been installed/reinstalled.

set -e

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics

# This should *only* run the benchmarks -- no perf tripwires, no GitHub issues, no running reports.
# So it shouldn't require GH tokens. It does *not* copy the benchmark raw data into yjit-metrics-pages
# since it doesn't run the reporting scripts.
# Note that on ARM, benchmark_and_update will automatically skip the stats config since it doesn't
# work on Graviton.
ruby continuous_reporting/benchmark_and_update.rb --benchmark-type smoketest --no-gh-issue --no-perf-tripwires --no-run-reports --bench-params=$BENCH_PARAMS --data-dir=continuous_reporting/single_iter_data

echo "Completed smoke-test benchmarking successfully."
