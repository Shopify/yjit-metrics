#!/bin/bash

# On older ARM64 chips like Graviton we can't do stats runs. That means no report that uses stats data can
# be completed. However, the blog_timeline report should be able to run with only prod YJIT data.

set -e

cd ~/ym/yjit-metrics

bundle

# Copy benchmark raw data into destination repo
#ruby continuous_reporting/file_benchmark_data_into_raw.rb -d continuous_reporting/data

# Generate reports, commit changes to Git.
ruby continuous_reporting/generate_and_upload_reports.rb --no-push --only-reports blog_timeline

echo "Minimal reporting check completed successfully."
