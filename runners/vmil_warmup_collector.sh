#!/bin/bash -l

set -e

WARMUPS=500
ITERATIONS=200

BASE_BENCH_OPTS="--skip-git-updates --warmup-itrs=$WARMUPS --min-bench-time=0.01 --on-error=report --configs=prod_ruby_with_yjit,ruby_30_with_mjit,prod_ruby_no_jit,truffleruby --min-bench-itrs=$ITERATIONS"
YJIT_STATS_BENCH_OPTS="--skip-git-updates --warmup-itrs=0 --min-bench-time=0.1 --configs=yjit_stats --min-bench-itrs=1"

# Running on Linux? Need to disable the appropriate things...
sudo ./setup.sh

./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS activerecord liquid-render lee 30k_ifelse psych-load railsbench 30k_methods optcarrot

# These are roughly ordered fastest-first.
./basic_benchmark.rb $BASE_BENCH_OPTS activerecord
./basic_benchmark.rb $BASE_BENCH_OPTS railsbench
