#!/bin/bash

set -e

cd ~/ym/yjit-metrics

bundle

ruby continuous_reporting/benchmark_and_update.rb --no-gh-issue --bench-params=$BENCH_PARAMS

echo "Completed benchmarking successfully."
