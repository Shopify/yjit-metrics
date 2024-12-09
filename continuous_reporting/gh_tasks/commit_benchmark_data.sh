#!/bin/bash

set -e

# TODO: most of this script needs to move into file_benchmark_data_into_raw, which can put it into the new location
# and/or do both. But it'll also get a lot of this into Ruby, which is a useful thing.

# If there is uncommitted data after a benchmark run, get it into (all?) raw_benchmarks where it belongs
cd ~/ym/yjit-metrics

bundle

# NOTE: This data dir is not configurable. If we run a smoke test
# into a different data dir we explicitly do not want to include that here.
# In that case this will run, find no data, and do nothing (which is what we want).
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
