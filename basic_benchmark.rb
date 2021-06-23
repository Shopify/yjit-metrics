#!/usr/bin/env ruby

# Clone the yjit-bench directory and run a variety of common comparison metrics.
# Usage: specify benchmarks to run as command line arguments.
#   You can also specify RUBY_CONFIG_OPTS to specify the arguments
#   that should be passed to Ruby's configuration script.

# This benchmark keeps two checkouts of YJIT so that we have debug and
# non-debug available. They are maintained at ../yjit-debug and ../yjit-prod.
# It also keeps a yjit-bench repository at ../yjit-bench.

require "optparse"

# Defaults
skip_git_updates = false
warmup_itrs = 15

OptionParser.new do |opts|
	opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

	opts.on("--skip-git-updates", "Skip updating Git repositories and rebuilding Ruby (omit on first run)") do
		skip_git_updates = true
	end

	opts.on("--warmup-itrs=n", "Number of warmup iterations that do not have recorded per-run timings") do |n|
		warmup_itrs = n
	end
end.parse!

benchmark_list = ARGV

require_relative "lib/yjit-metrics"

extra_config_options = []
if ENV["RUBY_CONFIG_OPTS"]
	extra_config_options = ENV["RUBY_CONFIG_OPTS"].split(" ")
elsif RUBY_PLATFORM["darwin"] && !`which brew`.empty?
	# On Mac with homebrew, default to Homebrew's OpenSSL location if not otherwise specified
	extra_config_options = [ "--with-openssl-dir=/usr/local/opt/openssl" ]
end

# These are quick - so we should run them up-front to fail out rapidly if something's wrong.
YJITMetrics.per_os_checks

# For this simple benchmark, store intermediate results in temp.json in the
# output data directory. In some cases it might make sense not to.
TEMP_DATA_PATH = File.expand_path(__dir__ + "/data")
OUTPUT_DATA_PATH = TEMP_DATA_PATH

CHRUBY_RUBIES = "#{ENV['HOME']}/.rubies"

### First, ensure up-to-date YJIT repos in debug configuration and prod configuration
BASE_CONFIG_OPTIONS = [ "--disable-install-doc", "--disable-install-rdoc" ]
YJIT_GIT_URL = "https://github.com/Shopify/yjit"
YJIT_GIT_BRANCH = "main"
PROD_YJIT_DIR = File.expand_path("#{__dir__}/../prod-yjit")
DEBUG_YJIT_DIR = File.expand_path("#{__dir__}/../debug-yjit")
unless skip_git_updates
	YJITMetrics.clone_ruby_repo_with path: PROD_YJIT_DIR,
	    git_url: YJIT_GIT_URL,
	    git_branch: YJIT_GIT_BRANCH,
	    install_to: CHRUBY_RUBIES + "/ruby-yjit-metrics-prod",
	    config_opts: BASE_CONFIG_OPTIONS + extra_config_options
	YJITMetrics.clone_ruby_repo_with path: DEBUG_YJIT_DIR,
		git_url: YJIT_GIT_URL,
		git_branch: YJIT_GIT_BRANCH,
		install_to: CHRUBY_RUBIES + "/ruby-yjit-metrics-debug",
		config_opts: BASE_CONFIG_OPTIONS + extra_config_options,
		config_env: ["CPPFLAGS=-DRUBY_DEBUG=1"]
end

### Second, ensure an up-to-date local yjit-bench checkout
YJIT_BENCH_GIT_URL = "https://github.com/Shopify/yjit-bench"
YJIT_BENCH_GIT_BRANCH = "main"
YJIT_BENCH_DIR = File.expand_path("#{__dir__}/../yjit-bench")
unless skip_git_updates
	YJITMetrics.clone_repo_with path: YJIT_BENCH_DIR, git_url: YJIT_BENCH_GIT_URL, git_branch: YJIT_BENCH_GIT_BRANCH
end

# For CI-style metrics collection we'll want timestamped results over time, not just the most recent.
timestamp = Time.now.getgm.strftime('%F-%H%M%S')

# Now run the benchmarks for debug YJIT
yjit_results = YJITMetrics.run_benchmarks(YJIT_BENCH_DIR, TEMP_DATA_PATH, ruby_opts: [], benchmark_list: benchmark_list, warmup_itrs: warmup_itrs, with_chruby: "ruby-yjit-metrics-debug")

json_path = OUTPUT_DATA_PATH + "/basic_benchmark_debug_#{timestamp}.json"
puts "Writing to JSON output file #{json_path}."
File.open(json_path, "w") { |f| f.write JSON.pretty_generate(yjit_results) }
