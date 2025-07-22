#!/bin/bash

set -e

cd ~/ym/yjit-metrics

bundle install

# Copy benchmark raw data into destination repo, generate reports, commit changes to Git.
ruby continuous_reporting/generate_and_upload_reports.rb

# Now we'll verify that we're not regenerating results when we shouldn't.
# To do that we'll tell generate_and_upload not to do Git checkins,
# and to fail if we try to generate any reports. The previous run
# was *supposed* to generate everything that needed it.
# If this fails, we're probably not reporting deterministically. Output
# should not change run-to-run with the same data.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push --prevent-regenerate

echo "Reporting and data upload completed successfully."
