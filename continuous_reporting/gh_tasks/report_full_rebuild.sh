#!/bin/bash -l

# This script assumes that benchmark_prep_task has been run first to clean, rebuild and reinstall.

set -e

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
# Also we're gonna be messing with the installed prerelease Rubies a fair bit.
chruby 3.0.2

cd ~/ym/yjit-metrics

# Copy benchmark raw data into yjit-metrics-pages repo, generate reports, commit changes to Git.
# The --regenerate-reports argument will regenerate ***all*** reports, which can take quite a
# long time. It will also occasionally hit a Ruby error, so we should update from 3.0.2 when
# we can for "system" Ruby here.
ruby continuous_reporting/generate_and_upload_reports.rb --regenerate-reports

# Now we'll verify that we're not regenerating results when we shouldn't.
# To do that we'll tell generate_and_upload not to do Git checkins,
# and to fail if we try to generate any reports. The previous run
# was *supposed* to generate everything that needed it.
# If this fails, we're probably not reporting deterministically. Output
# should not change run-to-run with the same data.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push --prevent-regenerate

echo "Reporting and data upload completed successfully."
