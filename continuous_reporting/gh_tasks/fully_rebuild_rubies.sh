#!/bin/bash

set -e

# This will uninstall all gems, among other side effects.
rm -rf ~/.rubies/ruby-yjit-metrics-debug/*
rm -rf ~/.rubies/ruby-yjit-metrics-prod/*
rm -rf ~/.rubies/ruby-yjit-metrics-stats/*

# This isn't a 100% cleanup -- no ./configure, for instance, which basic_benchmark.rb will only do if the current config looks wrong
cd ~/ym/prod-yjit && git clean -d -x -f
cd ~/ym/debug-yjit && git clean -d -x -f
cd ~/ym/stats-yjit && git clean -d -x -f

cd ~ubuntu/ym/yjit-bench
find . -wholename "*tmp/cache/bootsnap" -print0 | xargs -0 rm -r || echo OK

cd ~ubuntu/ym/yjit-metrics/
git pull
gem install bundler:2.2.30
bundle _2.2.30_
./basic_benchmark.rb -r 0 --bench-params=$BENCH_PARAMS # No benchmarking, but build and install everything at the appropriate SHA

echo "Benchmark CI Ruby reinstall completed successfully."
