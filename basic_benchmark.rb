#!/usr/bin/env ruby

# Clone the yjit-bench directory and run a variety of common comparison metrics.

# General-purpose benchmark management routines
require_relative "lib/yjit-metrics"

# These are quick - so we should run them up-front to fail out rapidly if something's wrong.
per_os_checks

# This benchmark keeps multiple checkouts of YJIT so that we have debug and non-debug available.
# It also keeps a yjit-bench repository

TEMP_DATA_PATH = File.expand_path(__dir__ + "/data")

### First, ensure up-to-date YJIT repos in debug configuration and prod configuration

BASE_CONFIG_OPTIONS = [ "--disable-install-doc", "--disable-install-rdoc", "--prefix=#{ENV['HOME']}/.rubies/ruby-yjit" ]
YJIT_GIT_URL = "https://github.com/Shopify/yjit"
YJIT_GIT_BRANCH = "main"
PROD_YJIT_DIR = File.expand_path("#{__dir__}/../prod-yjit")
DEBUG_YJIT_DIR = File.expand_path("#{__dir__}/../debug-yjit")

CHRUBY_RUBIES = "#{ENV['HOME']}/.rubies"

make_ruby_repo_with path: PROD_YJIT_DIR, git_url: YJIT_GIT_URL, git_branch: YJIT_GIT_BRANCH, install_to: CHRUBY_RUBIES + "/ruby-yjit-metrics-prod", config_opts: BASE_CONFIG_OPTIONS
make_ruby_repo_with path: DEBUG_YJIT_DIR, git_url: YJIT_GIT_URL, git_branch: YJIT_GIT_BRANCH, install_to: CHRUBY_RUBIES + "/ruby-yjit-metrics-debug", config_opts: BASE_CONFIG_OPTIONS, config_env: ["RUBY_DEBUG=1"]

### Second, ensure an up-to-date local yjit-bench checkout

YJIT_BENCH_GIT_URL = "https://github.com/Shopify/yjit-bench"
YJIT_BENCH_GIT_BRANCH = "main"
YJIT_BENCH_DIR = File.expand_path("#{__dir__}/../yjit-bench")

make_repo_with path: YJIT_BENCH_DIR, git_url: YJIT_BENCH_GIT_URL, git_branch: YJIT_BENCH_GIT_BRANCH

yjit_results = run_benchmarks(YJIT_BENCH_DIR, TEMP_DATA_PATH, ruby_opts: [], warmup_itrs: 15, with_chruby: "ruby-yjit-metrics-debug")

timestamp = Time.now.getgm.strftime('%F-%H%M%S')

File.open(TEMP_DATA_PATH + "/basic_benchmark_data_#{timestamp}.json", "w") { |f| f.write JSON.pretty_generate(yjit_results) }
