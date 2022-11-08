#!/bin/bash -l

# On older ARM64 chips like Graviton we can't do stats runs. That means no report that uses stats data can
# be completed. However, the blog_timeline report should be able to run with only prod YJIT data.

set -e

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics

# If we uncomment this, it'll run reporting but not benchmarking. That will file GH issues for perf drops.
# ruby continuous_reporting/benchmark_and_update.rb -b none

# Copy benchmark raw data into yjit-metrics-pages repo, generate reports, commit changes to Git.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push -d ./continuous_reporting/data --only-reports blog_timeline

# Don't keep the provisional report files around
cd ../yjit-metrics-pages && git checkout reports _includes

echo "Minimal reporting check completed successfully."
