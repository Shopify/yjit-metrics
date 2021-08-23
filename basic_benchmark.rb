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
require "fileutils"
require_relative "lib/yjit-metrics"

extra_config_options = []
if ENV["RUBY_CONFIG_OPTS"]
    extra_config_options = ENV["RUBY_CONFIG_OPTS"].split(" ")
elsif RUBY_PLATFORM["darwin"] && !`which brew`.empty?
    # On Mac with Homebrew, default to Homebrew's OpenSSL location if not otherwise specified
    extra_config_options = [ "--with-openssl-dir=/usr/local/opt/openssl" ]
end

# The same build of Ruby (e.g. current prerelease Ruby 3.1) can
# have several different runtime configs (e.g. MJIT vs YJIT vs interp.)
RUBY_BUILDS = {
    "ruby-yjit-metrics-debug" => {
        install: "repo",
        git_url: "https://github.com/Shopify/yjit",
        git_branch: "main",
        repo_path: File.expand_path("#{__dir__}/../debug-yjit"),
        config_opts: [ "--disable-install-doc", "--disable-install-rdoc" ] + extra_config_options,
        config_env: ["CPPFLAGS=-DRUBY_DEBUG=1"],
    },
    "ruby-yjit-metrics-prod" => {
        install: "repo",
        git_url: "https://github.com/Shopify/yjit",
        git_branch: "main",
        repo_path: File.expand_path("#{__dir__}/../prod-yjit"),
        config_opts: [ "--disable-install-doc", "--disable-install-rdoc" ] + extra_config_options,
    },
    "ruby-3.0.2" => {
        install: "ruby-install",
    },
    "truffleruby+graalvm-21.2.0" => {
        install: "ruby-build",
    },
}

RUBY_CONFIGS = {
    debug_ruby_no_yjit: {
        build: "ruby-yjit-metrics-debug",
        opts: [ "--disable-yjit" ],
    },
    yjit_stats: {
        build: "ruby-yjit-metrics-debug",
        opts: [ "--yjit", "--yjit-stats" ],
    },
    prod_ruby_no_jit: {
        build: "ruby-yjit-metrics-prod",
        opts: [ "--disable-yjit" ],
    },
    prod_ruby_with_yjit: {
        build: "ruby-yjit-metrics-prod",
        opts: [ "--yjit" ],
    },
    prod_ruby_with_mjit: {
        build: "ruby-yjit-metrics-prod",
        opts: [ "--jit --disable-yjit --jit-max-cache=10000 --jit-min-calls=10" ],
    },
    ruby_30: {
        build: "ruby-3.0.2",
        opts: [],
    },
    ruby_30_with_mjit: {
        build: "ruby-3.0.2",
        opts: [ "--jit --jit-max-cache=10000 --jit-min-calls=10" ],
        install: "ruby-install",
    },
    truffleruby: {
        build: "truffleruby+graalvm-21.2.0",
        opts: [ "--jvm" ],
    },
}
CONFIG_NAMES = RUBY_CONFIGS.keys

# Default settings for benchmark sampling
DEFAULT_WARMUP_ITRS = 15       # Number of un-reported warmup iterations to run before "counting" benchmark runs
DEFAULT_MIN_BENCH_ITRS = 10    # Minimum number of iterations to run each benchmark, regardless of time
DEFAULT_MIN_BENCH_TIME = 10.0  # Minimum time in seconds to run each benchmark, regardless of number of iterations

# Configuration for yjit-bench
YJIT_BENCH_GIT_URL = "https://github.com/Shopify/yjit-bench"
YJIT_BENCH_GIT_BRANCH = "main"
YJIT_BENCH_DIR = File.expand_path("#{__dir__}/../yjit-bench")

# Configuration for ruby-build
RUBY_BUILD_GIT_URL = "https://github.com/rbenv/ruby-build.git"
RUBY_BUILD_GIT_BRANCH = "master"
RUBY_BUILD_DIR = File.expand_path("#{__dir__}/../ruby-build")

ERROR_BEHAVIOURS = %i(die report ignore)

# Defaults
skip_git_updates = false
num_runs = 1   # For every run, execute the specified number of warmups and iterations in a new process
warmup_itrs = DEFAULT_WARMUP_ITRS
min_bench_itrs = DEFAULT_MIN_BENCH_ITRS
min_bench_time = DEFAULT_MIN_BENCH_TIME
DEFAULT_CONFIGS = [ :yjit_stats, :prod_ruby_with_yjit, :prod_ruby_no_jit ]
configs_to_test = DEFAULT_CONFIGS
when_error = :die

OptionParser.new do |opts|
    opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

    opts.on("--skip-git-updates", "Skip updating Git repositories and rebuilding Ruby (omit on first run)") do
        skip_git_updates = true
    end

    opts.on("--warmup-itrs=n", "Number of warmup iterations that do not have recorded per-run timings") do |n|
        warmup_itrs = n.to_i
        raise "Number of warmup iterations must be zero or positive!" if warmup_itrs < 0
    end

    opts.on("--min-bench-time=t", "Number of seconds minimum to run real benchmark iterations, default: 10.0") do |t|
        min_bench_time = t.to_f
        raise "min-bench-time must be zero or positive!" if min_bench_time < 0.0
    end

    opts.on("--min-bench-itrs=n", "Number of iterations minimum to run real benchmark iterations, default: 10") do |n|
        min_bench_itrs = n.to_i
        raise "min-bench-itrs must be zero or positive!" if min_bench_itrs < 0
    end

    opts.on("--runs=n", "Number of full process runs, with a new process and warmup iterations, default: 1") do |n|
        num_runs = n.to_i
        raise "Number of runs must be positive!" if num_runs <= 0
    end

    opts.on("--on-errors=BEHAVIOUR", "When a benchmark fails, how do we respond? Options: #{ERROR_BEHAVIOURS.map(&:to_s).join(",")}") do |choice|
        when_error = choice.to_sym
        unless ERROR_BEHAVIOURS.include?(when_error)
            raise "Unknown behaviour on error: #{choice.inspect}!"
        end
    end

    config_desc = "Comma-separated list of configurations to test" + "\n\t\t\tfrom: #{CONFIG_NAMES.join(", ")}\n\t\t\tdefault: #{DEFAULT_CONFIGS.join(",")}"
    opts.on("--configs=CONFIGS", config_desc) do |configs|
        configs_to_test = configs.split(",").map(&:strip).map(&:to_sym).uniq
        bad_configs = configs_to_test - CONFIG_NAMES
        raise "Requested test configuration(s) don't exist: #{bad_configs.inspect}!" unless bad_configs.empty?
    end
end.parse!

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

unless skip_git_updates
    builds_to_check = configs_to_test.map { |config| RUBY_CONFIGS[config][:build] }.uniq

    need_ruby_build = builds_to_check.any? { |build| RUBY_BUILDS[build][:install] == "ruby-build" }
    if need_ruby_build
        # ruby-build needs to be installed via sudo...
        if `which ruby-build`.strip == ""
            # No ruby-build installed. Make sure the repo is cloned and up to date, then tell the user to install it.
            YJITMetrics.clone_repo_with path: RUBY_BUILD_DIR, git_url: RUBY_BUILD_GIT_URL, git_branch: RUBY_BUILD_GIT_BRANCH

            puts "Ruby-build has been cloned to #{File.expand_path(RUBY_BUILD_DIR)}... From that directory, run 'sudo ./install.sh'."
            exit -1
        end
    end

    installed_rubies = Dir.glob("*", base: CHRUBY_RUBIES)

    builds_to_check.each do |ruby_build|
        build_info = RUBY_BUILDS[ruby_build]
        case build_info[:install]
        when "ruby-install"
            next if installed_rubies.include?(ruby_build)
            puts "Installing Ruby #{ruby_build} via ruby-install..."
            YJITMetrics.check_call("ruby-install #{ruby_build}")
        when "ruby-build"
            next if installed_rubies.include?(ruby_build)
            puts "Installing Ruby #{ruby_build} via ruby-build..."
            YJITMetrics.check_call("ruby-build #{ruby_build} ~/.rubies/#{ruby_build}")
        when "repo"
            YJITMetrics.clone_ruby_repo_with \
                path: build_info[:repo_path],
                git_url: build_info[:git_url],
                git_branch: build_info[:git_branch] || "main",
                install_to: CHRUBY_RUBIES + "/" + ruby_build,
                config_opts: build_info[:config_opts],
                config_env: build_info[:config_env] || []
        else
            raise "Unrecognized installation method: #{RUBY_BUILDS[ruby_build][:install].inspect}!"
        end
    end

    ### Ensure an up-to-date local yjit-bench checkout
    YJITMetrics.clone_repo_with path: YJIT_BENCH_DIR, git_url: YJIT_BENCH_GIT_URL, git_branch: YJIT_BENCH_GIT_BRANCH
end

# This will match ARGV-supplied benchmark names with canonical names and script paths in yjit-bench.
# It needs to happen *after* yjit-bench is cloned and updated.
benchmark_list = YJITMetrics::BenchmarkList.new name_list: ARGV, yjit_bench_path: YJIT_BENCH_DIR

# For CI-style metrics collection we'll want timestamped results over time, not just the most recent.
timestamp = Time.now.getgm.strftime('%F-%H%M%S')

# Create an "all_runs" entry for every tested combination of config/benchmark/run-number, then randomize the order.
all_runs = (0...num_runs).flat_map do |run_num|
    configs_to_test.flat_map do |config|
        benchmark_list.map do |bench_info|
            [ run_num, config, bench_info ]
        end
    end
end
all_runs = all_runs.sample(all_runs.size)

harness_settings = YJITMetrics::HarnessSettings.new({
    warmup_itrs: warmup_itrs,
    min_benchmark_itrs: min_bench_itrs,
    min_benchmark_time: min_bench_time,
})

# We write out intermediate files, allowing us to free data belonging to
# runs that have finished. That way if we do really massive runs, we're
# not holding onto a lot of memory for their results.
intermediate_by_config = {}
configs_to_test.each { |config| intermediate_by_config[config] = [] }

def write_crash_file(error_info, crash_report_dir)
    exc = error_info[:exception]
    bench = error_info[:benchmark_name]
    ruby = error_info[:shell_settings][:chruby]

    FileUtils.mkdir_p(crash_report_dir)

    error_text_path = "#{crash_report_dir}/output.txt"
    File.open(error_text_path, "w") do |f|
        f.print "Error in benchmark #{bench.inspect} with Ruby #{ruby.inspect}...\n"
        f.print "Exception #{exc.class}: #{exc.message}\n"
        f.print exc.full_message  # Includes backtrace and any cause/nested errors

        f.print "\n\n\nBenchmark harness information:\n\n"
        pp error_info[:output], f
        f.print "\n\n\nOutput of failing process:\n\n#{error_info[:output]}\n"
    end

    # Move any crash-related files into the crash report dir
    error_info[:crash_files].each { |f| FileUtils.mv f, "#{crash_report_dir}/" }
end

all_runs.each do |run_num, config, bench_info|
    puts "Next run: config #{config}  benchmark: #{bench_info[:name]}    run idx: #{run_num}"

    ruby = RUBY_CONFIGS[config][:build]
    ruby_opts = RUBY_CONFIGS[config][:opts]

    if num_runs > 1
        run_string = "%04d" % run_num + "_"
    else
        run_string = ""
    end

    on_error = proc do |error_info|
        exc = error_info[:exception]
        bench = error_info[:benchmark_name]

        puts "Exception in benchmark: #{error_info["benchmark_name"].inspect}, Ruby: #{ruby}, Error: #{exc.class} / #{exc.message.inspect}"

        # If we get a runtime error, we're not going to record this run's data.
        if when_error != :ignore
            # Instead we'll record the fact that we got an error.
            crash_report_dir = "#{OUTPUT_DATA_PATH}/#{timestamp}_crash_report_#{run_string}#{config}_#{bench}"
            write_crash_file(error_info, crash_report_dir)
        end

        # If we die on errors, raise or re-raise the exception.
        raise(exc) if when_error == :die
    end

    shell_settings = YJITMetrics::ShellSettings.new({
        ruby_opts: ruby_opts,
        chruby: ruby,
        on_error: on_error,
        enable_core_dumps: (when_error == :report ? true : false),
    })

    single_run_results = YJITMetrics.run_single_benchmark(bench_info, harness_settings: harness_settings, shell_settings: shell_settings)

    if single_run_results.nil?
        if when_error == :die
            raise "INTERNAL ERROR: NO DATA WAS RETURNED BUT WE'RE SUPPOSED TO HAVE AN UPTIGHT ERROR HANDLER. PLEASE EXAMINE WHAT WENT WRONG."
        end
        puts "No data collected for this run, presumably due to errors. On we go."
        next
    end

    json_path = OUTPUT_DATA_PATH + "/#{timestamp}_bb_intermediate_#{run_string}#{config}_#{bench_info[:name]}.json"
    puts "Writing to JSON output file #{json_path}."
    File.open(json_path, "w") { |f| f.write JSON.pretty_generate(single_run_results.to_json) }

    intermediate_by_config[config].push json_path
end

puts "All intermediate runs finished, merging to final files..."
intermediate_by_config.each do |config, int_files|
    run_data = int_files.map { |file| YJITMetrics::RunData.from_json JSON.load(File.read(file)) }
    merged_data = YJITMetrics.merge_benchmark_data(run_data)
    next if merged_data.nil?  # No non-error results? Skip it.

    # We should include how many runs we tried to do in each benchmark's metadata.
    merged_data["benchmark_metadata"].each do |bench_name, metadata|
        metadata["runs"] = num_runs
    end

    json_path = OUTPUT_DATA_PATH + "/#{timestamp}_basic_benchmark_#{config}.json"
    puts "Writing to JSON output file #{json_path}, removing intermediate files."
    File.open(json_path, "w") { |f| f.write JSON.pretty_generate(merged_data) }

    int_files.each { |f| FileUtils.rm_f f }
end

puts "All done."
