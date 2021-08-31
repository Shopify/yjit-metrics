#!/bin/bash

set -e

# I'm sure this shouldn't be necessary. But let's make sure env vars and chruby are set up, shall we?
. ~/.bashrc

# We'll use a released Ruby here to maximize the odds that the test harness runs even when YJIT is broken.
chruby 3.0.2

cd ~ubuntu/ym/yjit-metrics/
bundle
ruby continuous_reporting/benchmark_and_update.rb &> ~ubuntu/benchmark_ci_output.txt


# Want to install this? I recommend something like one of the following crontab entries:

# Twice a day, 12:05 am and pm
# 5 0,12 * * *		~ubuntu/ym/yjit-metrics/continuous_reporting/benchmark_cron_task.sh

# Hourly at XX:00 straight up
# 0 * * * *		~ubuntu/ym/yjit-metrics/continuous_reporting/benchmark_cron_task.sh
