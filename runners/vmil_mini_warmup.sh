#!/bin/bash -l

set -e

RUNS=20

BASE_BENCH_OPTS="--skip-git-updates --warmup-itrs=0 --runs=$RUNS --min-bench-time=0.1 --configs=prod_ruby_with_yjit,prod_ruby_with_mjit,prod_ruby_no_jit,truffleruby"
YJIT_STATS_BENCH_OPTS="--skip-git-updates --warmup-itrs=0 --min-bench-time=0.1 --configs=yjit_stats"

# Do a Git update on all the Rubies?
# Updating to head-of-master makes it hard to control config for real runs.
#./basic_benchmark.rb --min-bench-time=0.1 --min-bench-itrs=1 --warmup-itrs=0 --configs=yjit_stats,prod_ruby_with_yjit,prod_ruby_with_mjit,prod_ruby_no_jit activerecord

./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-time=1200 activerecord
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-time=1200 railsbench
