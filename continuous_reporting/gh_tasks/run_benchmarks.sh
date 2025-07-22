#!/bin/bash

set -e

cd ~/ym/yjit-metrics

bundle install

bundle exec continuous_reporting/benchmark_and_update.rb --bench-params=$BENCH_PARAMS

echo "Completed benchmarking successfully."
