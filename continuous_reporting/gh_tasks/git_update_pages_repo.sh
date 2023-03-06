#!/bin/bash -l

set -e

cd ~/ym/yjit-metrics-pages

# Don't mess with the raw_benchmarks directory in any way. Make sure yjit-metrics-pages is updated.

git fetch
git checkout .
git pull
git clean -d -f reports _includes
