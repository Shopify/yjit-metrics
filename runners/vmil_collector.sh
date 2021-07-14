#!/bin/bash -l

set -e

./basic_benchmark.rb --skip-git-updates --warmup-itrs=15 --min-bench-time=60.0 --min-bench-itrs=50 --configs=yjit_stats,prod_ruby_with_yjit,prod_ruby_with_mjit,prod_ruby_no_jit railsbench optcarrot activerecord jekyll liquid-render psych-load lee nbody
