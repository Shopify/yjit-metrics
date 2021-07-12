#!/bin/bash

set -e
set -x

# Commands to set up yjit-metrics as superuser

apt-get install -y sqlite3 libsqlite3-dev

sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'
sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'


