#!/bin/bash -l

set -e

WARMUPS=50

BASE_BENCH_OPTS="--skip-git-updates --warmup-itrs=$WARMUPS --min-bench-time=0.01 --on-error=report --configs=prod_ruby_with_yjit,ruby_30_with_mjit,prod_ruby_no_jit"
#YJIT_STATS_BENCH_OPTS="--skip-git-updates --warmup-itrs=$WARMUPS --min-bench-time=0.1 --configs=yjit_stats"

# Running on Linux? Need to disable the appropriate things...
# Since we're only doing 10 runs, I won't turn off ASLR.
sudo ./setup.sh

./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 activerecord
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 liquid-render
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 lee
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 30k_ifelse
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 psych-load
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 railsbench
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 30k_methods
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 optcarrot
