#!/bin/bash

set -e

# I'm sure this shouldn't be necessary. But let's make sure env vars and chruby are set up, shall we?
. ~/.bashrc

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

# This will uninstall all gems, among other side effects.
rm -rf ~/.rubies/ruby-yjit-metrics-debug/*
rm -rf ~/.rubies/ruby-yjit-metrics-prod/*
rm -rf ~/.gem/ruby/3.2.0

# This isn't a 100% cleanup -- no ./configure, for instance.
cd ~/ym/prod-yjit && make clean
cd ~/ym/debug-yjit && make clean

cd ~ubuntu/ym/yjit-bench
find . -wholename "*tmp/cache/bootsnap" -print0 | xargs -0 rm -r || echo OK

cd ~ubuntu/ym/yjit-metrics/
git pull
gem install bundler:2.2.30
bundle _2.2.30_
./basic_benchmark.rb -r 0  # No benchmarking, but build and install everything

echo "Preparation stage completed successfully."
