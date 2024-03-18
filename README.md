# YJIT Metrics

YJIT-metrics monitors speedups and internal statistics for Ruby JIT,
and especially for YJIT, an included JIT in CRuby. You can see
the latest YJIT statistics, gathered with yjit-metrics,
[at speed.yjit.org](https://speed.yjit.org).

YJIT-metrics uses the benchmarks in the
[yjit-bench repository](https://github.com/Shopify/yjit-bench).

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

You can run `./basic_benchmark.rb` to clone appropriate other repositories (yjit, yjit-bench) and run the benchmarks. You can also specify one or more benchmark names on the command line to run only those benchmarks: `./basic_benchmark.rb activerecord`

`basic_benchmark.rb` also accepts many other parameters, such as a `--skip-git-updates` parameter for runs after the first to not "git pull" its repos and rebuild Ruby.

To see full parameters, try `basic_benchmark.rb --help`

By default, `basic_benchmark`.rb will write JSON data files into the data directory after successful runs. You can then use reporting (see below) to get summaries of those results.

Use `basic_report.rb --help` to get started. There are several different reports, and you can specify which data files to include and which benchmarks to show. By default `basic_report.rb` will load all data files that have the exact same, most recent timestamp. So if `basic_benchmark.rb` writes several files, `basic_report.rb` will use them all by default.

You can find older examples of data-gathering scripts using `git log -- runners` (to see files that used to be in the "runners" directory) and post-processing scripts in the "formatters" directory.

## TruffleRuby

Our experience has been that the JVM (non-default) version gets better results than the native/SubstrateVM version, so if you are going to install a release we recommend the truffleruby+graalvm variant (with ruby-build) or truffleruby-graalvm (with ruby-install).

When you first try to run `basic_benchmark.rb` including a TruffleRuby configuration, `basic_benchmark.rb` will clone ruby-build and tell you how to install it. After you do so, run `basic_benchmark.rb` again and it will install TruffleRuby for you.

In general, `basic_benchmark.rb` will try to install or update the appropriate Ruby version(s) when you run it. If you run it with `--skip-git-updates` it will *not* attempt to install or update any Ruby configuration, nor yjit-bench, nor any of its other dependencies. If you want a partial installation or update you'll want to do it manually rather than relying on `basic_benchmark.rb`.

## Bugs, Questions and Contributions

We'd love your questions, your docs and code contributions, and just generally to talk with you about benchmarking YJIT!

Please see LICENSE.md, CODE_OF_CONDUCT.md and CONTRIBUTING.md for more information about this project and how to make changes.

Or, y'know, just talk to us. The authors have significant online presences and we love normal GitHub interaction like issues, pull requests and so on.

## Debugging Tips, Miscellaneous

Are you making changes to reporting, or otherwise making sure you're correctly handling benchmark data? `continuous_reporting/generate_and_upload_reports.rb` has a `--no-push` argument that lets you verify before you commit anything:

    chruby 3.0.2
    ruby continuous_reporting/generate_and_upload_reports.rb --no-push

Then a quick "git diff" in the pages directory can show you what, if anything, changed. The script will also print whether it found any pushable changes.
