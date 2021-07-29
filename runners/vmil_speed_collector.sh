#!/bin/bash -l

set -e

WARMUPS=500
RUNS=10

BASE_BENCH_OPTS="--skip-git-updates --warmup-itrs=$WARMUPS --runs=$RUNS --min-bench-time=0.1 --configs=prod_ruby_with_yjit,prod_ruby_with_mjit,prod_ruby_no_jit,truffleruby"
#YJIT_STATS_BENCH_OPTS="--skip-git-updates --warmup-itrs=$WARMUPS --min-bench-time=0.1 --configs=yjit_stats"

# Running on Linux? Need to disable the appropriate things...
sudo ./setup.sh

# Do a Git update on all the Rubies?
# Updating to head-of-master makes it hard to control config for real runs.
#./basic_benchmark.rb --min-bench-time=0.1 --min-bench-itrs=1 --warmup-itrs=0 --configs=yjit_stats,prod_ruby_with_yjit,truffleruby activerecord

# yjit_stats run with same warmup and iteration count will get accurate counter and coverage values
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 psych-load
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 30k_methods
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 30k_ifelse
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 lee
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 liquid-render
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 activerecord
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 optcarrot
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 jekyll
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=200 railsbench
