#!/bin/bash

set -e

cd ~/ym/yjit-metrics

bundle

# No timestamp given, default to right now
ruby continuous_reporting/create_json_params_file.rb --full-rebuild=$FULL_REBUILD --bench-type="$BENCH_TYPE" --yjit-metrics-name=$YJIT_METRICS_NAME --yjit-metrics-repo=$YJIT_METRICS_REPO --yjit-bench-name=$YJIT_BENCH_NAME --yjit-bench-repo=$YJIT_BENCH_REPO --cruby-name=$CRUBY_NAME --cruby-repo=$CRUBY_REPO --benchmark-data-dir=$BENCH_DATA_DIR

echo "Generated params successfully."
