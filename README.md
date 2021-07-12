# YJIT Metrics

## About this Repo

The code in this repo is intended to check speedups and internal YJIT statistics for
YJIT benchmarks in the [yjit-bench repository](https://github.com/Shopify/yjit-bench).
We hope to use it as part of a nightly run, generating and exporting data about
YJIT's progress on a variety of Ruby metrics.

## Setup and Installation

To run benchmarks on Linux, you'll need sudo access and to run the following command:

    sudo ./setup.sh

On Linux you'll need to do the same for each reboot, or do the following:

    sudo sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'
    sudo sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'

On Mac you don't need to do that, but you should expect benchmark accuracy will be slightly lower as a result.

## How to Use this Repo

You can run ./basic_benchmark.rb to clone appropriate other repositories (yjit, yjit-bench) and run the benchmarks. You can also specify one or more benchmark names on the command line to run only those benchmarks: `./basic_benchmark.rb yaml-load`

basic_benchmark.rb also accepts a --skip-git-updates parameter for runs after the first to not "git pull" its repos and rebuild Ruby.
