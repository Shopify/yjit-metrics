#!/bin/bash -l

set -e

# TODO: rename batches to runs
# TODO: add 30k_methods and 30k_ifelse

WARMUPS=15
RUNS=10

BASE_BENCH_OPTS="--skip-git-updates --warmup-itrs=$WARMUPS --runs=$RUNS --min-bench-time=0.1 --configs=prod_ruby_with_yjit,prod_ruby_with_mjit,prod_ruby_no_jit,truffleruby"
YJIT_STATS_BENCH_OPTS="--skip-git-updates --warmup-itrs=$WARMUPS --min-bench-time=0.1 --configs=yjit_stats"

# Do a Git update on all the Rubies?
# Updating to head-of-master makes it hard to control config for real runs.
#./basic_benchmark.rb --min-bench-time=0.1 --min-bench-itrs=1 --warmup-itrs=0 --configs=yjit_stats,prod_ruby_with_yjit,prod_ruby_with_mjit,prod_ruby_no_jit activerecord

# yjit_stats run with same warmup and iteration count will get accurate counter and coverage values
./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS --min-bench-itrs=12  psych-load
./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS --min-bench-itrs=17  lee
./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS --min-bench-itrs=150 liquid-render
./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS --min-bench-itrs=180 activerecord
./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS --min-bench-itrs=5   optcarrot
./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS --min-bench-itrs=3   jekyll
./basic_benchmark.rb $YJIT_STATS_BENCH_OPTS --min-bench-itrs=8   railsbench

# These iteration counts are chosen to be in the neighbourhood of 30 seconds on un-JITted CRuby
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=12  psych-load
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=17  lee
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=150 liquid-render
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=180 activerecord
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=5   optcarrot
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=3   jekyll
./basic_benchmark.rb $BASE_BENCH_OPTS --min-bench-itrs=8   railsbench
