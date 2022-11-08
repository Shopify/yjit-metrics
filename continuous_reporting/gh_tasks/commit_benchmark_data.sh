#!/bin/bash -l

set -e

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics-pages

# We've probably run reporting tests here. That leaves certain files dirty, but we don't want to check them in.
# We do *not* want to "git clean" because we have uncommitted test data.
git checkout Gemfile.lock _includes/reports reports

git pull
git add raw_benchmark_data
git commit -m "`uname -p` benchmark results"
git push

echo "Committed and pushed benchmark data successfully."
