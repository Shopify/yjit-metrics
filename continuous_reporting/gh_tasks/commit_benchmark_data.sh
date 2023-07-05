#!/bin/bash -l

set -e


# TODO: most of this script needs to move into file_benchmark_data_into_raw, which can put it into the new location
# and/or do both. But it'll also get a lot of this into Ruby, which is a useful thing.




# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

# If there is uncommitted data after a benchmark run, get it into (all?) raw_benchmarks where it belongs
cd ~/ym/yjit-metrics
ruby continuous_reporting/file_benchmark_data_into_raw.rb -d continuous_reporting/data

###### New repo - just for raw data

cd ~/ym/raw-benchmark-data

# Anything that's been added to a pending commit should be un-added
git restore --staged .

git pull

# This should commit only if there's anything to commit, but not fail if empty
git add raw_benchmark_data
git commit -m "`uname -p` benchmark results" || echo "Commit is empty?"
git push

echo "Committed and pushed benchmark data successfully."
