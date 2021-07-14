#!/bin/bash -l

set -e

# This isn't needed in prod, but it's nice to test scripts on our laptops
if [ -f /opt/dev/dev.sh ]
then
	. /opt/dev/dev.sh
fi

chruby ruby-yjit

./basic_benchmark.rb --skip-git-updates --warmup-itrs=15 --min-bench-time=60.0 --min-bench-itrs=50 --configs=yjit_stats,prod_ruby_with_yjit,prod_ruby_with_mjit,prod_ruby_no_jit railsbench optcarrot activerecord jekyll liquid-render psych-load lee nbody
