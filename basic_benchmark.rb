#!/usr/bin/env ruby

# Clone the yjit-bench directory and run benchmarks with various Rubies.
# Usage: specify benchmarks to run as command line arguments.
#   You can also specify RUBY_CONFIG_OPTS to specify the arguments
#   that should be passed to Ruby's configuration script.

# This benchmark keeps two checkouts of YJIT so that we have debug and
# non-debug available. They are maintained at ../yjit-debug and ../yjit-prod.
# It also keeps a yjit-bench repository at ../yjit-bench.

# The intention is that basic_benchmark can be used to collect benchmark
# results, and then basic_report can be used to show reports for those
# benchmarks.

require "optparse"
require_relative "lib/yjit-metrics"

# I prefer human-readable names for configs, where I can get them.
# TODO: move Ruby config options here?
TEST_RUBY_CONFIGS = {
	debug_ruby_no_yjit: {
		ruby: "ruby-yjit-metrics-debug",
		opts: [ "--disable-yjit" ],
	},
	yjit_stats: {
		ruby: "ruby-yjit-metrics-debug",
		opts: [ "--yjit", "--yjit-stats" ],
	},
	prod_ruby_no_jit: {
		ruby: "ruby-yjit-metrics-prod",
		opts: [ "--disable-yjit" ],
	},
	prod_ruby_with_yjit: {
		ruby: "ruby-yjit-metrics-prod",
		opts: [ "--yjit" ],
	},
	prod_ruby_with_mjit: {
		ruby: "ruby-yjit-metrics-prod",
		opts: [ "--jit --disable-yjit" ],
	},
	ruby_27: {
		ruby: "2.7.2",
		opts: [],
	},
	ruby_27_with_mjit: {
		ruby: "2.7.2",
		opts: [ "--jit" ],
	},
}
TEST_CONFIG_NAMES = TEST_RUBY_CONFIGS.keys

# Default settings for benchmark sampling
DEFAULT_WARMUP_ITRS = 15       # Number of un-reported warmup iterations to run before "counting" benchmark runs
DEFAULT_MIN_BENCH_ITRS = 10    # Minimum number of iterations to run each benchmark, regardless of time
DEFAULT_MIN_BENCH_TIME = 10.0  # Minimum time in seconds to run each benchmark, regardless of number of iterations

# Configuration for YJIT Rubies, debug and prod
BASE_CONFIG_OPTIONS = [ "--disable-install-doc", "--disable-install-rdoc" ]
YJIT_GIT_URL = "https://github.com/Shopify/yjit"
YJIT_GIT_BRANCH = "main"
PROD_YJIT_DIR = File.expand_path("#{__dir__}/../prod-yjit")
DEBUG_YJIT_DIR = File.expand_path("#{__dir__}/../debug-yjit")

# Configuration for yjit-bench
YJIT_BENCH_GIT_URL = "https://github.com/Shopify/yjit-bench"
YJIT_BENCH_GIT_BRANCH = "main" #"bench_setup_fixes"
YJIT_BENCH_DIR = File.expand_path("#{__dir__}/../yjit-bench")

# Defaults
skip_git_updates = false
num_batches = 1   # For every batch, run the specified number of warmups and iterations in a new process
warmup_itrs = DEFAULT_WARMUP_ITRS
min_bench_itrs = DEFAULT_MIN_BENCH_ITRS
min_bench_time = DEFAULT_MIN_BENCH_TIME
DEFAULT_TEST_CONFIGS = [ :yjit_stats, :prod_ruby_with_yjit, :prod_ruby_no_jit ]
configs_to_test = DEFAULT_TEST_CONFIGS

OptionParser.new do |opts|
	opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

	opts.on("--skip-git-updates", "Skip updating Git repositories and rebuilding Ruby (omit on first run)") do
		skip_git_updates = true
	end

	opts.on("--warmup-itrs=n", "Number of warmup iterations that do not have recorded per-run timings") do |n|
		warmup_itrs = n.to_i
		raise "Number of warmup iterations must be zero or positive!" if n < 0
	end

	opts.on("--min-bench-time=t", "Number of seconds minimum to run real benchmark iterations, default: 10.0") do |t|
		min_bench_time = t.to_f
		raise "min-bench-time must be zero or positive!" if n < 0.0
	end

	opts.on("--min-bench-itrs=n", "Number of iterations minimum to run real benchmark iterations, default: 10") do |n|
		min_bench_itrs = n.to_i
		raise "min-bench-itrs must be zero or positive!" if n < 0
	end

	opts.on("--batches=n", "Number of full process runs, with a new process and warmup iterations, default: 1") do |n|
		num_batches = n.to_i
		raise "Number of batches must be positive!" if n <= 0
	end

	config_desc = "Comma-separated list of configurations to test" + "\n\t\t\tfrom: #{TEST_CONFIG_NAMES.join(", ")}\n\t\t\tdefault: #{DEFAULT_TEST_CONFIGS.join(",")}"
	opts.on("--configs=CONFIGS", config_desc) do |configs|
		configs_to_test = configs.split(",").map(&:strip).map(&:to_sym).uniq
		bad_configs = configs_to_test - TEST_CONFIG_NAMES
		raise "Requested test configuration(s) don't exist: #{bad_configs.inspect}!" unless bad_configs.empty?
	end
end.parse!

benchmark_list = ARGV

extra_config_options = []
if ENV["RUBY_CONFIG_OPTS"]
	extra_config_options = ENV["RUBY_CONFIG_OPTS"].split(" ")
elsif RUBY_PLATFORM["darwin"] && !`which brew`.empty?
	# On Mac with Homebrew, default to Homebrew's OpenSSL location if not otherwise specified
	extra_config_options = [ "--with-openssl-dir=/usr/local/opt/openssl" ]
end

# These are quick - so we should run them up-front to fail out rapidly if something's wrong.
YJITMetrics.per_os_checks

# For this simple benchmark, store intermediate results in temp.json in the
# output data directory. In some cases it might make sense not to.
TEMP_DATA_PATH = File.expand_path(__dir__ + "/data")
OUTPUT_DATA_PATH = TEMP_DATA_PATH

CHRUBY_RUBIES = "#{ENV['HOME']}/.rubies"

installed_rubies = Dir[CHRUBY_RUBIES + "/*"].to_a
unless installed_rubies.any? { |ruby_name| ruby_name.end_with?("/ruby-2.7.2") }
	YJITMetrics.check_call("ruby-install ruby-2.7.2")
end

### First, ensure up-to-date YJIT repos in debug configuration and prod configuration

if !skip_git_updates && configs_to_test.any? { |config| TEST_RUBY_CONFIGS[config][:ruby] == "ruby-yjit-metrics-prod" }
	YJITMetrics.clone_ruby_repo_with path: PROD_YJIT_DIR,
	    git_url: YJIT_GIT_URL,
	    git_branch: YJIT_GIT_BRANCH,
	    install_to: CHRUBY_RUBIES + "/ruby-yjit-metrics-prod",
	    config_opts: BASE_CONFIG_OPTIONS + extra_config_options
end

if !skip_git_updates && configs_to_test.any? { |config| TEST_RUBY_CONFIGS[config][:ruby] == "ruby-yjit-metrics-debug" }
	YJITMetrics.clone_ruby_repo_with path: DEBUG_YJIT_DIR,
		git_url: YJIT_GIT_URL,
		git_branch: YJIT_GIT_BRANCH,
		install_to: CHRUBY_RUBIES + "/ruby-yjit-metrics-debug",
		config_opts: BASE_CONFIG_OPTIONS + extra_config_options,
		config_env: ["CPPFLAGS=-DRUBY_DEBUG=1"]
end

### Second, ensure an up-to-date local yjit-bench checkout

if !skip_git_updates
	YJITMetrics.clone_repo_with path: YJIT_BENCH_DIR, git_url: YJIT_BENCH_GIT_URL, git_branch: YJIT_BENCH_GIT_BRANCH
end

# For CI-style metrics collection we'll want timestamped results over time, not just the most recent.
timestamp = Time.now.getgm.strftime('%F-%H%M%S')

all_batches = (0...num_batches).flat_map { |batch_num| configs_to_test.map { |config| [ batch_num, config ] } }
all_batches = all_batches.sample(all_batches.size) # Randomise the order of the list of batches

all_batches.each do |batch_num, config|
	ruby = TEST_RUBY_CONFIGS[config][:ruby]
	ruby_opts = TEST_RUBY_CONFIGS[config][:opts]
	yjit_results = YJITMetrics.run_benchmarks(
		YJIT_BENCH_DIR,
		TEMP_DATA_PATH,
		with_chruby: ruby,
		ruby_opts: ruby_opts,
		benchmark_list: benchmark_list,
		warmup_itrs: warmup_itrs,
		min_benchmark_itrs: min_bench_itrs,
		min_benchmark_time: min_bench_time
		)

	if num_batches > 1
		batch_string = "%04d" % batch_num + "_"
	else
		batch_string = ""
	end

	json_path = OUTPUT_DATA_PATH + "/#{timestamp}_basic_benchmark_#{batch_string}_#{config}.json"
	puts "Writing to JSON output file #{json_path}."
	File.open(json_path, "w") { |f| f.write JSON.pretty_generate(yjit_results) }
end
