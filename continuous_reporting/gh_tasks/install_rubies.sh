#!/bin/bash
set -e

cd ~/ym/yjit-metrics

bundle install

BENCH_PARAMS_ARG=""
if [[ -n "$BENCH_PARAMS" ]]; then
  BENCH_PARAMS_ARG="--bench-params=$BENCH_PARAMS"
fi

OUTPUT=$(bundle exec continuous_reporting/install_rubies.rb $BENCH_PARAMS_ARG)
echo "$OUTPUT"

BENCHMARK_RUBY_PATH=$(echo "$OUTPUT" | grep "^BENCHMARK_RUBY_PATH=" | cut -d= -f2 || true)
BENCHMARK_DATE=$(echo "$OUTPUT" | grep "^BENCHMARK_DATE=" | cut -d= -f2 || true)

export BENCHMARK_RUBY_PATH
export BENCHMARK_DATE
