#!/bin/bash -l
# Note: may need a login shell, depending how chruby is installed.

# This script assumes that Rubies have already been installed/reinstalled.

set -e

# NOTE: the intention is for this script to go away, as benchmark_and_update gets more of its behaviour from
# the bench_params.json file. Single-iter benchmark runs become a build param, not a separate script.

chruby 3.0.2

cd ~/ym/yjit-metrics

bundle

ruby continuous_reporting/benchmark_and_update.rb --benchmark-type smoketest --no-gh-issue --no-perf-tripwires --bench-params=$BENCH_PARAMS --data-dir=continuous_reporting/single_iter_data

echo "Completed smoke-test benchmarking successfully."
