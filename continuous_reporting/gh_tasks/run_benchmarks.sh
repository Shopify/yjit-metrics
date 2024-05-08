#!/bin/bash -l
# Note: may need a login shell, depending how chruby is installed.

set -e

chruby 3.0.2
cd ~/ym/yjit-metrics

bundle

ruby continuous_reporting/benchmark_and_update.rb --no-gh-issue --no-perf-tripwires --bench-params=$BENCH_PARAMS

echo "Completed benchmarking successfully."
