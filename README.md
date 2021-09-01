# YJIT Metrics

YJIT-metrics is intended to check speedups and internal statistics for YJIT,
an experimental open-source JIT for Ruby. You can find out more about YJIT
[at its GitHub repo](https://github.com/Shopify/yjit).

YJIT-metrics uses the benchmarks in the
[yjit-bench repository](https://github.com/Shopify/yjit-bench).

You can see the latest benchmark reports
[on the yjit-metrics GitHub Pages URL](https://shopify.github.io/yjit-metrics).

## Setup and Installation, Accuracy of Results

To run benchmarks on Linux, you'll need sudo access and to run the following command:

    sudo ./setup.sh

You'll need to do the same for each reboot, or do the following:

    sudo sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'
    sudo sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'

On Mac you don't need to do that, but you should expect benchmark accuracy will be lower. Anecdotally it's hard to measure differences less than 3% on a Mac for a number of reasons (background processes, CPU turbo/speed settings, generally lower CRuby focus on Mac performance).

Also Mac timings of some operations are substantially different &mdash; not only will you need to run more iterations for accuracy, but the correct measurement will be different in many cases. CRuby has significant known performance problems on the Mac, and YJIT reflects that (e.g. the setivar microbenchmark.)

For that reason, where we-the-authors provide official numbers they will usually be AWS c5.metal instances, often with dedicated-host tenancy.

## How to Use this Repo

You can run ./basic_benchmark.rb to clone appropriate other repositories (yjit, yjit-bench) and run the benchmarks. You can also specify one or more benchmark names on the command line to run only those benchmarks: `./basic_benchmark.rb yaml-load`

basic_benchmark.rb also accepts a --skip-git-updates parameter for runs after the first to not "git pull" its repos and rebuild Ruby. To see full parameters, try `basic_benchmark.rb --help`

By default, basic_benchmark.rb will write JSON data files into the data directory after successful runs. You can then use reporting (see below) to get descriptions of those results.

Try `basic_report.rb` and `basic_report.rb --help` to get started. There are several different reports, and you can specify which data files to include and which benchmarks to show. By default basic_report will load all data files that have the exact same, most recent timestamp. So if basic_benchmark.rb writes several files, basic_report.rb will use them all by default.

You can find examples of data-gathering scripts in the "runners" directory and postprocessing scripts in the "formatters" directory.

## TruffleRuby

While it's possible to install TruffleRuby via ruby-install, our experience has been that the JVM (non-default) version gets better results than the native/SubstrateVM version available via ruby-install. So: you're probably going to need to install ruby-build and install it yourself.

(Eventually yjit-metrics will do this for you.)

First, clone ruby-build and install it under /usr/local/bin:

    $ git clone https://github.com/rbenv/ruby-build.git
    $ cd ruby-build
    $ sudo install.sh

Then basic_benchmark.rb will install the appropriate TruffleRuby next time you run it without --skip-git-updates.
