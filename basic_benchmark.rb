#!/usr/bin/env ruby

# Clone the yjit-bench directory and run benchmarks with various Rubies.
# Usage: specify benchmarks to run as command line arguments.
#   You can also specify RUBY_CONFIG_OPTS to specify the arguments
#   that should be passed to Ruby's configuration script.

# This benchmark keeps multiple checkouts of YJIT so that we have
# configurations for production, debug, stats and potentially others
# over time.
# It also keeps a yjit-bench repository at ../yjit-bench.

# The intention is that basic_benchmark can be used to collect benchmark
# results, and then basic_report can be used to show reports for those
# benchmarks.

START_TIME = Time.now

require "benchmark"
require "optparse"
require "fileutils"
require "etc"
require_relative "lib/yjit_metrics"

# Default settings for benchmark sampling
DEFAULT_MIN_BENCH_ITRS = 10    # Minimum number of iterations to run each benchmark, regardless of time
DEFAULT_MIN_BENCH_TIME = 10.0  # Minimum time in seconds to run each benchmark, regardless of number of iterations

ERROR_BEHAVIOURS = %i(die report ignore)

# Use "quiet" mode since yjit-bench will record the runtime stats in the json file anyway.
# Having the text stats print out makes it harder to report stderr on failures.
YJIT_STATS_OPTS = [ "--yjit-stats=quiet" ]

YJIT_ENABLED_OPTS = [ "--yjit" ]
NO_JIT_OPTS = [ "--disable-yjit" ]

SETARCH_OPTS = {
    linux: "setarch #{`uname -m`.strip} -R taskset -c #{Etc.nprocessors - 1}",
}

CRUBY_PER_OS_OPTS = SETARCH_OPTS
YJIT_PER_OS_OPTS = SETARCH_OPTS
TRUFFLE_PER_OS_OPTS = {}

PREV_RUBY_BUILD = "ruby-yjit-metrics-prev"

# These are "config roots" because they define a configuration
# in a non-platform-specific way. They're really several *variables*
# that partially define a configuration.
#
# In this case they define how the Ruby was built, and then what
# command-line params we run it with.
#
# Right now we use the config name itself to communicate this data
# to the reporting tasks. That's bad and we should stop :-/
# NOTE: to use "ruby-abc" with --skip-git-updates and no full rebuild just insert: "ruby-abc" => {build: "ruby-abc", opts: SOME_JIT_OPTS, per_os_prefix: CRUBY_PER_OS_OPTS}
RUBY_CONFIG_ROOTS = {
    "debug_ruby_no_yjit" => {
        build: "ruby-yjit-metrics-debug",
        opts: NO_JIT_OPTS,
        per_os_prefix: CRUBY_PER_OS_OPTS,
    },
    "yjit_stats" => {
        build: "ruby-yjit-metrics-stats",
        opts: YJIT_ENABLED_OPTS + YJIT_STATS_OPTS,
        per_os_prefix: YJIT_PER_OS_OPTS,
    },
    "yjit_prod_stats" => {
        build: "ruby-yjit-metrics-stats",
        opts: YJIT_ENABLED_OPTS + YJIT_STATS_OPTS,
        per_os_prefix: YJIT_PER_OS_OPTS,
    },
    "yjit_prod_stats_disabled" => {
        build: "ruby-yjit-metrics-stats",
        opts: YJIT_ENABLED_OPTS,
        per_os_prefix: YJIT_PER_OS_OPTS,
    },
    "prod_ruby_no_jit" => {
        build: "ruby-yjit-metrics-prod",
        opts: NO_JIT_OPTS,
        per_os_prefix: CRUBY_PER_OS_OPTS,
    },
    "prod_ruby_with_yjit" => {
        build: "ruby-yjit-metrics-prod",
        opts: YJIT_ENABLED_OPTS,
        per_os_prefix: YJIT_PER_OS_OPTS,
    },
    "prev_ruby_no_jit" => {
        build: PREV_RUBY_BUILD,
        opts: NO_JIT_OPTS,
        per_os_prefix: CRUBY_PER_OS_OPTS,
    },
    "prev_ruby_yjit" => {
        build: PREV_RUBY_BUILD,
        opts: YJIT_ENABLED_OPTS,
        per_os_prefix: YJIT_PER_OS_OPTS,
    },
}

RUBY_CONFIGS = {}
YJITMetrics::PLATFORMS.each do |platform|
    RUBY_CONFIG_ROOTS.each do |config_root, data|
        config_name = "#{platform}_#{config_root}"
        RUBY_CONFIGS[config_name] = data
    end
end

CONFIG_NAMES = RUBY_CONFIGS.keys
THIS_PLATFORM_CONFIGS = RUBY_CONFIGS.keys.select do |config|
    config_platform = YJITMetrics::PLATFORMS.detect { |plat| config.start_with?(plat) }
    config_platform == YJITMetrics::PLATFORM
end

# Defaults
skip_git_updates = false
num_runs = 1   # For every run, execute the specified number of warmups and iterations in a new process
harness_params = {
    variable_warmup_config_file: nil,
    min_bench_itrs: DEFAULT_MIN_BENCH_ITRS,
    min_bench_time: DEFAULT_MIN_BENCH_TIME,
}
DEFAULT_CONFIGS = %w(yjit_stats prod_ruby_with_yjit prod_ruby_no_jit prev_ruby_yjit prev_ruby_no_jit)
configs_to_test = DEFAULT_CONFIGS.map { |config| "#{YJITMetrics::PLATFORM}_#{config}"}
bench_data = nil
when_error = :report
output_path = "data"
bundler_version = nil
# For CI-style metrics collection we'll want timestamped results over time, not just the most recent.
timestamp = START_TIME.getgm.strftime('%F-%H%M%S')
full_rebuild = false
max_attempts = 3
failed_benchmarks = {}

OptionParser.new do |opts|
    opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

    opts.on("--skip-git-updates", "Skip updating Git repositories and rebuilding Ruby (only works if Rubies are built already)") do
        skip_git_updates = true
    end

    opts.on("--variable-warmup-config-file=FILENAME", "JSON file with per-Ruby, per-benchmark configuration for warmup, iterations, etc.") do |filename|
        raise "Variable warmup config file #{filename.inspect} does not exist!" unless File.exist?(filename)
        harness_params[:variable_warmup_config_file] = filename
        harness_params[:warmup_itrs] = harness_params[:min_bench_itrs] = harness_params[:min_bench_time] = nil
    end

    opts.on("--warmup-itrs=n", "Number of warmup iterations that do not count in per-run summaries") do |n|
        raise "Must not specify warmup/itrs configuration along with a warmup config file!" if harness_params[:variable_warmup_config_file]
        raise "Number of warmup iterations must be zero or positive!" if n.to_i < 0
        harness_params[:warmup_itrs] = n.to_i
    end

    opts.on("--min-bench-time=t", "--min-benchmark-time=t", "Number of seconds minimum to run real benchmark iterations, default: 10.0") do |t|
        raise "Must not specify warmup/itrs configuration along with a warmup config file!" if harness_params[:variable_warmup_config_file]
        raise "min-bench-time must be zero or positive!" if t.to_f < 0.0
        harness_params[:min_bench_time] = t.to_f
    end

    opts.on("--min-bench-itrs=n", "--min-benchmark-itrs=t", "Number of iterations minimum to run real benchmark iterations, default: 10") do |n|
        raise "Must not specify warmup/itrs configuration along with a warmup config file!" if harness_params[:variable_warmup_config_file]
        raise "min-bench-itrs must be zero or positive!" if n.to_i < 0
        harness_params[:min_bench_itrs] = n.to_i
    end

    opts.on("--runs=n", "Number of full process runs, with a new process and warmup iterations, default: 1 (0 to only install, no benchmarks)") do |n|
        raise "Number of runs must be positive or zero!" if n.to_i < 0
        num_runs = n.to_i
    end

    opts.on("--output DIR", "Write output files to the specified directory") do |dir|
        output_path = dir
    end

    opts.on("--bundler-version=VERSION", "Require a specific Bundler version (default: 2.2.30)") do |ver|
        bundler_version = ver
    end

    opts.on("--max-retries=NUMBER", "Number of times to retry a benchmark after it fails. (default: #{max_attempts - 1})") do |n|
        raise "max-retries must be zero or positive!" if n.to_i < 0
        max_attempts = n.to_i + 1
    end

    opts.on("--on-errors=BEHAVIOUR", "When a benchmark fails, how do we respond? Options: #{ERROR_BEHAVIOURS.map(&:to_s).join(",")}") do |choice|
        when_error = choice.to_sym
        unless ERROR_BEHAVIOURS.include?(when_error)
            raise "Unknown behaviour on error: #{choice.inspect}!"
        end
    end

    opts.on("--bench-params=BENCH_PARAMS.json", "--bp=BENCH_PARAMS.json") do |bp|
        unless File.exist?(bp)
            raise "No such bench params file: #{bp.inspect}!"
        end
        bench_data = JSON.load File.read(bp)
        ts = bench_data["ts"]
        unless ts =~ /\A\d{4}-\d{2}-\d{2}-\d{6}\Z/
            raise "Bad format for given timestamp: #{ts.inspect}!"
        end
        full_rebuild = bench_data["full_rebuild"]
        timestamp = ts
    end

    opts.on("-fr=YN", "--full-rebuild=YN", "Whether to fully rebuild all rubies") do |fr|
        if fr.nil? || fr.strip == ""
            full_rebuild = true
        else
            full_rebuild = YJITMetrics::CLI.human_string_to_boolean(fr)
        end
    end

    config_desc = "Comma-separated list of Ruby configurations to test" + "\n\t\t\tfrom: #{CONFIG_NAMES.join(", ")}\n\t\t\tdefault: #{DEFAULT_CONFIGS.join(",")}"
    opts.on("--configs=CONFIGS", config_desc) do |configs|
        configs_to_test = configs.split(",").map(&:strip).map { |s| s.gsub('PLATFORM', YJITMetrics::PLATFORM) }.uniq
        bad_configs = configs_to_test - CONFIG_NAMES
        raise "Requested test configuration(s) don't exist: #{bad_configs.inspect}!\n\nLegal configs include: #{CONFIG_NAMES.inspect}" unless bad_configs.empty?
        wrong_platform_configs = configs_to_test - THIS_PLATFORM_CONFIGS
        raise "Requested configuration(s) are are not for platform #{YJITMetrics::PLATFORM}: #{wrong_platform_configs.inspect}!" unless wrong_platform_configs.empty?
    end
end.parse!

HARNESS_PARAMS = harness_params
BENCH_DATA = bench_data || {}
FULL_REBUILD = full_rebuild

STDERR.puts <<HERE
basic_benchmark.rb:
  harness_params = #{harness_params.inspect}
  bench_data: #{bench_data.inspect}
  full_rebuild: #{full_rebuild.inspect}
  output_path: #{output_path.inspect}
  benchmarks: #{ARGV.inspect}
HERE

extra_config_options = []
if ENV["RUBY_CONFIG_OPTS"]
    extra_config_options = ENV["RUBY_CONFIG_OPTS"].split(" ")
elsif RUBY_PLATFORM["darwin"] && !`which brew`.empty?
    # On Mac with Homebrew, default to Homebrew's OpenSSL 1.1 location if not otherwise specified
    ossl_prefix = `brew --prefix openssl@1.1`.chomp
    extra_config_options = [ "--with-openssl-dir=#{ossl_prefix}" ]
end

# Git repo url for CRuby.
YJIT_GIT_URL = BENCH_DATA["cruby_repo"] || "https://github.com/ruby/ruby"
# Git branch to build for "prod" yjit.
YJIT_GIT_BRANCH = BENCH_DATA["cruby_sha"] || "master"
# In order to build "prev" ruby the same way we build "prod" ruby
# we build it from source, so we use a tag that represents a recent release.
YJIT_PREV_REF = "v3_3_6"

def full_clean_yjit_cruby(flavor)
    repo = File.expand_path("#{__dir__}/../#{flavor}-yjit")
    "if test -d #{repo}; then cd #{repo} && git clean -d -x -f; fi && rm -rf ~/.rubies/ruby-yjit-metrics-#{flavor}"
end

# The same build of Ruby (e.g. current prerelease Ruby) can
# have several different runtime configs (e.g. YJIT vs interp.)
repo_root = File.expand_path("#{__dir__}/..")
install_root = "~/.rubies"
RUBY_BUILDS = {
    "ruby-yjit-metrics-debug" => {
        install: "repo",
        git_url: YJIT_GIT_URL,
        git_branch: YJIT_GIT_BRANCH,
        repo_path: "#{repo_root}/debug-yjit",
        config_opts: [ "--disable-install-doc", "--disable-install-rdoc", "--enable-yjit=dev" ] + extra_config_options,
        config_env: ["CPPFLAGS=-DRUBY_DEBUG=1"],
        full_clean: full_clean_yjit_cruby("debug"),
    },
    "ruby-yjit-metrics-stats" => {
        install: "repo",
        git_url: YJIT_GIT_URL,
        git_branch: YJIT_GIT_BRANCH,
        repo_path: "#{repo_root}/stats-yjit",
        config_opts: [ "--disable-install-doc", "--disable-install-rdoc", "--enable-yjit=stats" ] + extra_config_options,
        full_clean: full_clean_yjit_cruby("stats"),
    },
    "ruby-yjit-metrics-prod" => {
        install: "repo",
        git_url: YJIT_GIT_URL,
        git_branch: YJIT_GIT_BRANCH,
        repo_path: "#{repo_root}/prod-yjit",
        config_opts: [ "--disable-install-doc", "--disable-install-rdoc", "--enable-yjit" ] + extra_config_options,
        full_clean: full_clean_yjit_cruby("prod"),
    },
    PREV_RUBY_BUILD => {
        install: "repo",
        git_url: YJIT_GIT_URL,
        git_branch: YJIT_PREV_REF,
        repo_path: "#{repo_root}/prev-yjit",
        config_opts: [ "--disable-install-doc", "--disable-install-rdoc", "--enable-yjit" ] + extra_config_options,
        full_clean: full_clean_yjit_cruby("prev"),
    },
    "truffleruby+graalvm-21.2.0" => {
        install: "ruby-build",
        full_clean: "rm -rf ~/.rubies/truffleruby+graalvm-21.2.0",
    },
    # can also do "name" => { install: "ruby-build", full_clean: "rm -rf ~/.rubies/name" }
}

SKIPPED_COMBOS = [
    # Discourse broken by 1e9939dae24db232d6f3693630fa37a382e1a6d7, 16th June
    # Needs an update of dependency libraries.
    # Note: check back to see when/if Discourse runs with head-of-master Ruby again...
    [ "*", "discourse" ],

    # [ "name_of_config", "name_of_benchmark" ] OR
    # [ "*", "name_of_benchmark" ]
]

YJIT_METRICS_DIR = __dir__

# Configuration for yjit-bench
YJIT_BENCH_GIT_URL = BENCH_DATA["yjit_bench_repo"] || "https://github.com/Shopify/yjit-bench.git"
YJIT_BENCH_GIT_BRANCH = BENCH_DATA["yjit_bench_sha"] || "main"
YJIT_BENCH_DIR = ENV["YJIT_BENCH_DIR"] || File.expand_path("../yjit-bench", __dir__)

# Configuration for ruby-build
RUBY_BUILD_GIT_URL = "https://github.com/rbenv/ruby-build.git"
RUBY_BUILD_GIT_BRANCH = "master"
RUBY_BUILD_DIR = File.expand_path("#{__dir__}/../ruby-build")

# These are quick - so we should run them up-front to fail out rapidly if something's wrong.
YJITMetrics.per_os_checks

OUTPUT_DATA_PATH = output_path[0] == "/" ? output_path : File.expand_path("#{__dir__}/#{output_path}")

RUBIES = "#{ENV['HOME']}/.rubies"

# Check which OS we are running
def this_os
    @os ||= (
      host_os = RbConfig::CONFIG['host_os']
      case host_os
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        :windows
      when /darwin|mac os/
        :macosx
      when /linux/
        :linux
      when /solaris|bsd/
        :unix
      else
        raise "unknown os: #{host_os.inspect}"
      end
    )
end

if FULL_REBUILD && skip_git_updates
    raise "You won't like what happens with full-rebuild plus skip-git-updates! If using a config where full-rebuild won't matter, then turn it off!"
end

if FULL_REBUILD
    puts "Remove old Rubies for full rebuild"
    configs_to_test.map { |config| RUBY_CONFIGS[config][:build] }.uniq.each do |build_to_clean|
        YJITMetrics.check_call RUBY_BUILDS[build_to_clean][:full_clean]
    end
end

unless skip_git_updates
    builds_to_check = configs_to_test.map { |config| RUBY_CONFIGS[config][:build] }.uniq

    need_ruby_build = builds_to_check.any? { |build| RUBY_BUILDS[build][:install] == "ruby-build" }
    if need_ruby_build
        if !File.exist?(RUBY_BUILD_DIR)
            YJITMetrics.clone_repo_with path: RUBY_BUILD_DIR, git_url: RUBY_BUILD_GIT_URL, git_branch: RUBY_BUILD_GIT_BRANCH

        end
    end

    installed_rubies = Dir.glob("*", base: RUBIES)

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
            Dir.chdir(RUBY_BUILD_DIR) do
              YJITMetrics.check_call("git pull")
              YJITMetrics.check_call("RUBY_CONFIGURE_OPTS=--disable-shared ./bin/ruby-build #{ruby_build.sub(/^ruby-/, '')} #{RUBIES}/#{ruby_build}")
            end
        when "repo"
            YJITMetrics.clone_ruby_repo_with \
                path: build_info[:repo_path],
                git_url: build_info[:git_url],
                git_branch: build_info[:git_branch] || "main",
                install_to: RUBIES + "/" + ruby_build,
                config_opts: build_info[:config_opts],
                config_env: build_info[:config_env] || []
        else
            raise "Unrecognized installation method: #{RUBY_BUILDS[ruby_build][:install].inspect}!"
        end
    end

    ### Ensure an up-to-date local yjit-bench checkout
    YJITMetrics.clone_repo_with path: YJIT_BENCH_DIR, git_url: YJIT_BENCH_GIT_URL, git_branch: YJIT_BENCH_GIT_BRANCH
end

# All appropriate repos have been cloned, correct branch/SHA checked out, etc. Now log the SHAs.

def sha_for_dir(dir)
    Dir.chdir(dir) { `git rev-parse HEAD`.chomp }
end

# TODO: figure out how/whether to handle cases with --skip-git-update where we have a not-committed Git version.
# Right now that will just reflect the current head revision in Git, not any changes to it.
# For now if we're testing a specific version, this will say which one.
GIT_VERSIONS = {
    "yjit_bench" => sha_for_dir(YJIT_BENCH_DIR),
    "yjit_metrics" => sha_for_dir(YJIT_METRICS_DIR),
}

if BENCH_DATA["yjit_metrics_sha"] && GIT_VERSIONS["yjit_metrics"] != BENCH_DATA["yjit_metrics_sha"]
    raise "YJIT-Metrics SHA in benchmark data disagrees with actual tested version!"
end

# Rails apps in yjit-bench can leave a bad bootsnap cache - delete them
Dir.glob("**/*tmp/cache/bootsnap", base: YJIT_BENCH_DIR) { |f| FileUtils.rmtree File.join(YJIT_BENCH_DIR, f) }

# This will match ARGV-supplied benchmark names with canonical names and script paths in yjit-bench.
# It needs to happen *after* yjit-bench is cloned and updated.
benchmark_list = YJITMetrics::BenchmarkList.new name_list: ARGV, yjit_bench_path: YJIT_BENCH_DIR

def harness_settings_for_config_and_bench(config, bench)
    if HARNESS_PARAMS[:variable_warmup_config_file]
        @variable_warmup_settings ||= JSON.parse(File.read HARNESS_PARAMS[:variable_warmup_config_file])
        @hs_by_config_and_bench ||= {}
        @hs_by_config_and_bench[config] ||= {}

        if @variable_warmup_settings[config] && @variable_warmup_settings[config][bench]
            @hs_by_config_and_bench[config][bench] ||= YJITMetrics::HarnessSettings.new({
                warmup_itrs: @variable_warmup_settings[config][bench]["warmup_itrs"],
                min_benchmark_itrs: @variable_warmup_settings[config][bench]["min_bench_itrs"] || 15,
                min_benchmark_time: @variable_warmup_settings[config][bench]["min_bench_time"] || 0,
            })
        elsif YJITMetrics::DEFAULT_YJIT_BENCH_CI_SETTINGS["configs"][config]
            defaults = YJITMetrics::DEFAULT_YJIT_BENCH_CI_SETTINGS["configs"][config]
            # This benchmark hasn't been run before. Use default settings for this config until we've finished a run.
            @hs_by_config_and_bench[config][bench] ||= YJITMetrics::HarnessSettings.new({
                warmup_itrs: defaults["max_warmup_itrs"],
                min_benchmark_itrs: defaults["min_bench_itrs"] || 15,
                min_benchmark_time: 0,
            })
        else
            # This benchmark hasn't been run before and we don't have config-specific defaults. Oof.
            @hs_by_config_and_bench[config][bench] ||= YJITMetrics::HarnessSettings.new({
                warmup_itrs: nil,
                min_benchmark_itrs: YJITMetrics::DEFAULT_YJIT_BENCH_CI_SETTINGS["min_bench_itrs"],
                min_benchmark_time: 0,
            })
        end
        return @hs_by_config_and_bench[config][bench]
    else
        @harness_settings ||= YJITMetrics::HarnessSettings.new({
            warmup_itrs: HARNESS_PARAMS[:warmup_itrs],
            min_benchmark_itrs: HARNESS_PARAMS[:min_bench_itrs],
            min_benchmark_time: HARNESS_PARAMS[:min_bench_time],
        })
        return @harness_settings
    end
end

# Create an "all_runs" entry for every tested combination of config/benchmark/run-number, then randomize the order.
all_runs = (0...num_runs).flat_map do |run_num|
    configs_to_test.flat_map do |config|
        benchmark_list.to_a.flat_map do |bench_info|
            bench_info[:name] = bench_info[:name].delete_suffix('.rb')
            if SKIPPED_COMBOS.include?([ "*", bench_info[:name] ]) ||
              SKIPPED_COMBOS.include?([ config, bench_info[:name] ])
                puts "Skipping: #{config} / #{bench_info[:name]}..."
                []
            else
                [ [ run_num, config, bench_info ] ]
            end
        end
    end
end
all_runs = all_runs.sample(all_runs.size)

# We write out intermediate files, allowing us to free data belonging to
# runs that have finished. That way if we do really massive runs, we're
# not holding onto a lot of memory for their results.
intermediate_by_config = {}
configs_to_test.each { |config| intermediate_by_config[config] = [] }

def write_crash_file(error_info, crash_report_dir)
    exc = error_info[:exception]
    bench = error_info[:benchmark_name]
    ruby = error_info[:shell_settings][:ruby]

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

def load_averages
  file = '/proc/loadavg'
  File.readable?(file) ? File.read(file).strip : `uptime`.match(/load averages?: ([0-9., ]+)/)[1].gsub(/,/, '')
end

load_averages_before = load_averages

Dir.chdir(YJIT_BENCH_DIR) do
    all_runs.each.with_index do |(run_num, config, bench_info), progress_idx|
      Benchmark.realtime do
        puts "## [#{Time.now}] Next run: config #{config}  benchmark: #{bench_info[:name]}  run idx: #{run_num}  progress: #{progress_idx + 1}/#{all_runs.size}"

        ruby = RUBY_CONFIGS[config][:build]
        ruby_opts = RUBY_CONFIGS[config][:opts]
        per_os_prefix = RUBY_CONFIGS[config][:per_os_prefix]

        # Right now we don't have a great place to put per-benchmark metrics that *change*
        # for each run. "Benchmark" metadata means constant for each type of benchmark.
        # Instead, like peak_mem_bytes, we just have to put it at the top-level.
        # TODO: fix that.
        re_run_num = 0

        if num_runs > 1
            run_string = "%04d" % run_num + "_"
        else
            run_string = ""
        end

        on_error = proc do |error_info|
            exc = error_info[:exception]
            bench = error_info[:benchmark_name]

            re_run_info = ""
            re_run_info = " (attempt ##{re_run_num + 1}/#{max_attempts})" if max_attempts > 1

            puts "Exception in benchmark #{bench} w/ config #{config}#{re_run_info}: #{error_info["benchmark_name"].inspect}, Ruby: #{ruby}, Error: #{exc.class} / #{exc.message.inspect}"

            # If we get a runtime error, we're not going to record this run's data.
            if [:die, :report].include?(when_error)
                # Instead we'll record the fact that we got an error.
                crash_report_dir = "#{OUTPUT_DATA_PATH}/#{timestamp}_crash_report_#{run_string}#{config}_#{bench}"
                write_crash_file(error_info, crash_report_dir)
            end
        end

        shell_settings = YJITMetrics::ShellSettings.new({
            ruby_opts: ruby_opts,
            prefix: per_os_prefix[this_os],
            ruby: ruby,
            on_error: on_error,
            enable_core_dumps: (when_error == :report ? true : false),
            bundler_version: bundler_version,
        })

        single_run_results = nil
        loop do
            single_run_results = YJITMetrics.run_single_benchmark(bench_info,
                harness_settings: harness_settings_for_config_and_bench(config, bench_info[:name]),
                shell_settings: shell_settings)

            break if single_run_results.success? # Got results? Great! Then don't die or re-run.

            ((failed_benchmarks[config] ||= {})[bench_info[:name]] ||= []) << {
              exit_status: single_run_results.exit_status,
              summary: single_run_results.summary,
            }

            raise single_run_results.error if when_error == :die

            puts "No data collected for this run, presumably due to errors. On we go."

            re_run_num += 1
            break if re_run_num >= max_attempts
        end

        # Single-run results will be ErrorData if we're reporting or ignoring errors.
        # If we die on error, we should raise an exception before we get here.
        if single_run_results.success?
            single_run_results["failures_before_success"] = re_run_num # Always 0 unless max_attempts > 1

            json_path = OUTPUT_DATA_PATH + "/#{timestamp}_bb_intermediate_#{run_string}#{config}_#{bench_info[:name]}.json"
            puts "Writing to JSON output file #{json_path}."
            File.open(json_path, "w") { |f| f.write JSON.pretty_generate(single_run_results.to_json) }

            intermediate_by_config[config].push json_path
        end
      end.tap do |time|
        printf "## took %.2fs for %s %s\n", time, config, bench_info[:name]
      end
    end
end

END_TIME = Time.now

total_elapsed = END_TIME - START_TIME
total_seconds = total_elapsed.to_i
total_minutes = total_seconds / 60
total_hours = total_minutes / 60
seconds = total_seconds % 60
minutes = total_minutes % 60

# Make a hash of {"prod_yjit" => ["--yjit"]} to keep a record of the ruby opts used for each config.
ruby_config_opts = configs_to_test.inject({}) do |h, config|
  h.merge(YJITMetrics.config_without_platform(config) => RUBY_CONFIGS[config][:opts])
end

puts "All intermediate runs finished, merging to final files..."
intermediate_by_config.each do |config, int_files|
    run_data = int_files.map { |file| YJITMetrics::RunData.from_json JSON.load(File.read(file)) }
    merged_data = YJITMetrics.merge_benchmark_data(run_data)
    next if merged_data.nil?  # No non-error results? Skip it.

    # Extra metadata tags for overall benchmarks
    merged_data["benchmark_metadata"].each do |bench_name, metadata|
        metadata["runs"] = num_runs # how many runs we tried to do
    end

    merged_data["ruby_config_name"] = config
    merged_data["benchmark_failures"] = failed_benchmarks[config]

    # Items in "full_run" should be the same for any run included in this timestamp group
    # (so nothing specific to this execution since we merge results from multiple machines).
    merged_data["full_run"] = {
        "git_versions" => GIT_VERSIONS, # yjit-metrics version, yjit-bench version, etc.
        "ruby_config_opts" => ruby_config_opts, # command-line options for each Ruby configuration
    }

    # Extra is a top-level key for anything that might be interesting but isn't used.
    merged_data["extra"] = {
        # Include total time for the whole run, not just this benchmark,
        # to monitor how long large jobs run for.
        "total_bench_time" => "#{total_hours} hours, #{minutes} minutes, #{seconds} seconds",
        "total_bench_seconds" => total_seconds,
        "load_before" => load_averages_before,
        "load_after" => load_averages,
    }

    json_path = OUTPUT_DATA_PATH + "/#{timestamp}_basic_benchmark_#{config}.json"
    puts "Writing to JSON output file #{json_path}, removing intermediate files."
    File.open(json_path, "w") { |f| f.write JSON.pretty_generate(merged_data) }

    int_files.each { |f| FileUtils.rm_f f }
end

summary = if failed_benchmarks.empty?
  "All benchmarks completed successfully.\n"
else
  by_failure = failed_benchmarks.each_with_object({}) do |(config, failures), h|
    failures.each do |name, results|
      results.each do |info|
        ((h[name] ||= {})[info.values_at(:exit_status, :summary)] ||= []) << config
      end
    end
  end

  decorate = ->(s) { "\e[1m#{s}\e[0m" }

  lines = ["Benchmark failures:\n"]

  lines += by_failure.map do |name, failures|
    # failures is {[exit, msg] => [config1, config2],}
    "#{decorate[name]} (#{failures.values.flatten.sort.uniq.join(", ")})"
  end

  lines << "\nDetails:\n"

  lines += by_failure.map do |(name, results)|
    [
      "#{decorate[name]}\n",
      results.map do |(exit_status, summary), configs|
        "exit status #{exit_status} (#{configs.sort.uniq.join(", ")})\n#{summary}\n"
      end
    ]
  end

  lines.flatten.join("\n")
end

puts "\n#{summary}\n"

puts "All done, total benchmarking time #{total_hours} hours, #{minutes} minutes, #{seconds} seconds."

exit(failed_benchmarks.empty? ? 0 : 1)
