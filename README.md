# YJIT Metrics

YJIT-metrics monitors speedups and internal statistics for Ruby JIT,
and especially for YJIT, an included JIT in CRuby. You can see
the latest YJIT statistics, gathered with yjit-metrics,
[at speed.ruby-lang.org](https://speed.ruby-lang.org).

YJIT-metrics uses the benchmarks in the
[ruby-bench repository](https://github.com/ruby/ruby-bench).

## Setup and Installation, Accuracy of Results

To run benchmarks on Linux, you'll need sudo access and to run the following command:

    ./setup.sh cpu

You'll need to do the same for each reboot, or do the following:

    sudo sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'
    sudo sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'

On Mac you don't need to do that, but you should expect benchmark accuracy will be lower. Anecdotally it's hard to measure differences less than 3% on a Mac for a number of reasons (background processes, CPU turbo/speed settings, generally lower CRuby focus on Mac performance).

Also Mac timings of some operations are substantially different &mdash; not only will you need to run more iterations for accuracy, but the correct measurement will be different in many cases. CRuby has significant known performance problems on the Mac, and YJIT reflects that (e.g. the setivar microbenchmark.)

For that reason, where we-the-authors provide official numbers they will usually be AWS c5.metal instances, often with dedicated-host tenancy.

## How to Use this Repo

### Benchmark data

You can run `./basic_benchmark.rb` to clone appropriate other repositories (yjit, ruby-bench) and run the benchmarks. You can also specify one or more benchmark names on the command line to run only those benchmarks: `./basic_benchmark.rb activerecord`

`basic_benchmark.rb` also accepts many other parameters, such as a `--skip-git-updates` parameter for runs after the first to not "git pull" its repos and rebuild Ruby.

To see full parameters, try `basic_benchmark.rb --help`

By default, `basic_benchmark`.rb will write JSON data files into the data directory after successful runs. You can then use reporting (see below) to get summaries of those results.

Use `basic_report.rb --help` to get started. There are several different reports, and you can specify which data files to include and which benchmarks to show. By default `basic_report.rb` will load all data files that have the exact same, most recent timestamp. So if `basic_benchmark.rb` writes several files, `basic_report.rb` will use them all by default.

You can find older examples of data-gathering scripts using `git log -- runners` (to see files that used to be in the "runners" directory) and `git log -- formatters` for post-processing scripts in the old "formatters" directory.


### speed.ruby-lang.org site

After collecting some data with `basic_benchmark.rb` you can generate the html
site (hosted at speed.ruby-lang.org) with a simple command:

`site/exe serve`

This will move files from `./data/` into a `build` directory,
generate all the html files, and start a web server where you can view the site at `localhost:8000`.

Some of the reports are built using `lib/yjit_metrics` and have templates in
`lib/yjit_metrics/report_templates`.
The rest of the files that build the site are found beneath `site`.
There are `erb` files to generate additional pages
and the script that does all the file rendering in `site/_framework/`.


## TruffleRuby

Our experience has been that the JVM (non-default) version gets better results than the native/SubstrateVM version, so if you are going to install a release we recommend the truffleruby+graalvm variant (with ruby-build) or truffleruby-graalvm (with ruby-install).

When you first try to run `basic_benchmark.rb` including a TruffleRuby configuration, `basic_benchmark.rb` will clone ruby-build and tell you how to install it. After you do so, run `basic_benchmark.rb` again and it will install TruffleRuby for you.

In general, `basic_benchmark.rb` will try to install or update the appropriate Ruby version(s) when you run it. If you run it with `--skip-git-updates` it will *not* attempt to install or update any Ruby configuration, nor ruby-bench, nor any of its other dependencies. If you want a partial installation or update you'll want to do it manually rather than relying on `basic_benchmark.rb`.

## Bugs, Questions and Contributions

We'd love your questions, your docs and code contributions, and just generally to talk with you about benchmarking YJIT!

Please see LICENSE.md, CODE_OF_CONDUCT.md and CONTRIBUTING.md for more information about this project and how to make changes.

Or, y'know, just talk to us. The authors have significant online presences and we love normal GitHub interaction like issues, pull requests and so on.

## Debugging Tips, Miscellaneous

Are you making changes to reporting, or otherwise making sure you're correctly handling benchmark data? `continuous_reporting/generate_and_upload_reports.rb` has a `--no-push` argument that lets you verify before you commit anything:

    ruby continuous_reporting/generate_and_upload_reports.rb --no-push

Then a quick "git diff" in the pages directory can show you what, if anything, changed. The script will also print whether it found any pushable changes.

### Output Format

Changes to the JSON format may require a bump to the `version` entry (`lib/yjit-metrics.rb`)
and translation logic in the code that processes the data (`lib/yjit_metrics/result_set.rb`).

### Tests

The test files can be run with a command like `ruby -Ilib:test test/some_test.rb`.

#### `test/basic_benchmark_script_test.rb`

This can be used as a smoke test to run the main script and verify the output JSON data files.
This is useful to test changes to the `basic_benchmark.rb` script and will provide much faster feedback than triggering a test of the branch in CI.

#### `test/slack_notification.rb`

Along with `test/generate_slack_data.sh` this test can be used to verify that
the slack notification builds correctly.
