#!/bin/bash -l

set -e

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics
git pull

# Copy benchmark raw data into yjit-metrics-pages repo
#ruby continuous_reporting/file_benchmark_data_into_raw.rb -d continuous_reporting/data

# Copy benchmark raw data into yjit-metrics-pages repo, generate reports, commit changes to Git.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push

# Don't keep the provisional report files around
cd ../yjit-metrics-pages && git checkout reports _includes

echo "Reporting check completed successfully."
