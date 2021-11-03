#!/bin/bash

set -e

# I'm sure this shouldn't be necessary. But let's make sure env vars and chruby are set up, shall we?
. ~/.bashrc

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
chruby 3.0.2

cd ~ubuntu/ym/yjit-metrics/
git pull
gem install bundler:1.17.2
bundle
ruby continuous_reporting/benchmark_and_update.rb

# Now we'll verify that we're not regenerating results when we shouldn't.
# To do that we'll tell generate_and_upload not to do Git checkins,
# and to fail if we try to generate any reports. The previous run
# was *supposed* to generate everything that needed it.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push --prevent-regenerate

echo "Completed successfully."
