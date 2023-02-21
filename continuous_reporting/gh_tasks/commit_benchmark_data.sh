#!/bin/bash -l

set -e

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

# If there is uncommitted data after a benchmark run, get it into raw_benchmarks where it belongs
cd ~/ym/yjit-metrics
ruby continuous_reporting/file_benchmark_data_into_raw.rb -d continuous_reporting/data

cd ~/ym/yjit-metrics-pages

# Anything that's been added to a pending commit should be un-added
git restore --staged .

# We've probably run reporting tests here. Get rid of uncommitted changes to reports, etc.
git checkout Gemfile.lock _includes/reports reports

# Clean only the report dirs. We might have uncommitted test data, so no cleaning data dirs.
git clean -d -f _includes/reports reports

git pull

# Sometimes we make a commit at the exact same time as the x86 worker and then we can't
# push it. If that has happened, rebase our data commit back over top of the new head commit.
pushd ../yjit-metrics-pages
git pull --rebase
popd

# This should commit only if there's anything to commit, but not fail if empty
git add raw_benchmark_data
git commit -m "`uname -p` benchmark results" || echo "Commit is empty?"
git push

echo "Committed and pushed benchmark data successfully."
