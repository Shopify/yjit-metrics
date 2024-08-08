#!/bin/bash

set -e

cd ~/ym/yjit-metrics
git pull

bundle

# Copy benchmark raw data into destination repo
#ruby continuous_reporting/file_benchmark_data_into_raw.rb -d continuous_reporting/data

# Copy benchmark raw data into destination repo, generate reports, commit changes to Git.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push

echo "Reporting check completed successfully."
