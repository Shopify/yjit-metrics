#!/usr/bin/env ruby

require_relative "../lib/yjit_metrics"

require 'fileutils'
require 'net/http'

require "yaml"
require "optparse"
require 'rbconfig'

# TODO: should the benchmark-run and perf-check parts of this script be separated? Probably.

# This is intended to be the top-level script for running benchmarks, reporting on them
# and checking performance.

# The tolerances below are for detecting big drops in benchmark performance. So far I haven't
# had good luck with that -- it's either too sensitive and files spurious bugs a lot, or it's
# too insensitive and doesn't notice real bugs. Right now, auto-filing bugs is turned off.

# The STDDEV_TOLERANCE is what multiple of the standard deviation it's okay to drop on
# a given run. That effectively determines the false-positive rate since we're comparing samples
# from a Gaussian-ish distribution.
NORMAL_STDDEV_TOLERANCE = 1.5
# The DROP_TOLERANCE is what absolute multiple-of-the-mean drop (e.g. 0.05 means 5%) is
# assumed to be okay. For each metric we use the more permissive of the two tolerances
# on the more permissive of the two mean values. All four must be outside of tolerance
# for us to count a failure.
NORMAL_DROP_TOLERANCE = 0.07
# A microbenchmark will normally have a very small stddev from run to run. That means
# it's actually *less* tolerant of noise on the host, since "twice the stddev" is a
# significantly smaller absolute value.
MICRO_STDDEV_TOLERANCE = 2.0
# A microbenchmark will routinely show persistent speed changes of much larger magnitude
# than a larger, more varied benchmark. For example, setivar is surprisingly prone to
# large swings in time taken depending on tiny changes to memory layout. So the drop
# tolerance needs to be significantly larger to avoid frequent false positives.
MICRO_DROP_TOLERANCE = 0.20

BUILT_REPORTS_ROOT = YJITMetrics::ContinuousReporting::BUILT_REPORTS_ROOT
RAW_BENCHMARK_ROOT = YJITMetrics::ContinuousReporting::RAW_BENCHMARK_ROOT

YM_REPORT_DIR = File.expand_path "#{BUILT_REPORTS_ROOT}/_includes/reports/"
# NOTE: Variable warmup is currently disabled pending an investigation and refactor.
VAR_WARMUP_FILE = if false # File.exist?(YM_REPORT_DIR)
    var_warmup_reports = Dir.glob(YM_REPORT_DIR + "/variable_warmup_*.warmup_settings.json").to_a
    # Grab the most recent
    var_warmup_reports.sort[-1]
end

puts "Running benchmarks on #{YJITMetrics::PLATFORM}"

def platform_for_config(config_name)
    p = YJITMetrics::PLATFORMS.detect { |platform| config_name.start_with?(platform) }
    raise("No platform name for config: #{config_name.inspect}!") unless p
    p
end

DEFAULT_CI_CONFIGS_ALL = YJITMetrics::DEFAULT_YJIT_BENCH_CI_SETTINGS["configs"].keys
DEFAULT_CI_CONFIGS = {}
DEFAULT_CI_CONFIGS_ALL.each do |config|
    p = platform_for_config(config)
    DEFAULT_CI_CONFIGS[p] ||= []
    DEFAULT_CI_CONFIGS[p] << config
end

# If we have a config file from the variable warmup report, we should use it. If not,
# we should have defaults to fall back on.
DEFAULT_CI_COMMAND_LINE = "--on-errors=report --max-retries=2 " +
    (VAR_WARMUP_FILE && File.exist?(VAR_WARMUP_FILE) ?
        "--variable-warmup-config-file=#{VAR_WARMUP_FILE}" :
        "--warmup-itrs=10 --min-bench-time=30.0 --min-bench-itrs=10") +
    " --configs=#{DEFAULT_CI_CONFIGS[YJITMetrics::PLATFORM].join(",")}"

BENCH_TYPES = {
    "none"       => "",
    "default"    => DEFAULT_CI_COMMAND_LINE,
    "smoketest"  => "--warmup-itrs=0   --min-bench-time=0.0 --min-bench-itrs=1 --on-errors=die --configs=PLATFORM_prod_ruby_no_jit,PLATFORM_prod_ruby_with_yjit",
    #"minimal"    => "--warmup-itrs=1   --min-bench-time=10.0  --min-bench-itrs=5    --on-errors=report --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit activerecord lee 30k_methods",
    #"extended"   => "--warmup-itrs=500 --min-bench-time=120.0 --min-bench-itrs=1000 --runs=3 --on-errors=report --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit,truffleruby",
}
def args_for_bench_type(bench_type_arg)
    if bench_type_arg.include?("-")
        bench_type_arg.gsub("PLATFORM", YJITMetrics::PLATFORM)
    elsif BENCH_TYPES.has_key?(bench_type_arg)
        BENCH_TYPES[bench_type_arg].gsub("PLATFORM", YJITMetrics::PLATFORM)
    else
        raise "Unrecognized benchmark args or type: #{bench_type_arg.inspect}! Known types: #{BENCH_TYPES.keys.inspect}"
    end
end

benchmark_args = nil
bench_params_file = nil
should_file_gh_issue = true
no_perf_tripwires = false
all_perf_tripwires = false
single_perf_tripwire = nil
is_verbose = false
data_dir = nil
full_rebuild = nil

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: benchmark_and_update.rb [options]

        Example benchmark args: "#{BENCH_TYPES["smoketest"]}"
    BANNER

    opts.on("-b BENCHTYPE", "--benchmark-type BENCHTYPE", "The type of benchmarks to run - give a basic_benchmark.rb command line, or one of: #{BENCH_TYPES.keys.inspect}") do |btype|
      benchmark_args = args_for_bench_type(btype)
    end

    # NOTE: GH issue filing is currently disabled
    opts.on("-g", "--no-gh-issue", "Do not file an actual GitHub issue, only print failures to console") do
        should_file_gh_issue = false
    end

    opts.on("-a", "--all-perf-tripwires", "Check performance tripwires on all pairs of benchmarks (implies --no-gh-issue)") do
        if no_perf_tripwires || single_perf_tripwire
            raise "Error! Please do not specify --all-perf-tripwires along with --no-perf-tripwires or --single-perf-tripwire!"
        end
        all_perf_tripwires = true
        should_file_gh_issue = false
    end

    opts.on("-t TS", "--perf-timestamp TIMESTAMP", "Check performance tripwire at this specific timestamp") do |ts|
        if all_perf_tripwires || no_perf_tripwires
            raise "Error! Please do not specify a specific perf tripwire along with --no-perf-tripwires or --all-perf-tripwires!"
        end
        single_perf_tripwire = ts.strip
    end

    opts.on("-np", "--no-perf-tripwires", "Do not check performance tripwires") do
        if all_perf_tripwires || single_perf_tripwire
            raise "Error! Please do not specify --no-perf-tripwires along with --single-perf-tripwire or --all-perf-tripwires!"
        end
        no_perf_tripwires = true
    end

    opts.on("-fr YN", "--full-rebuild YN") do |fr|
        if fr.nil? || fr.strip == ""
            full_rebuild = true
        else
            full_rebuild = YJITMetrics.CLI.human_string_to_boolean(fr)
        end
    end

    opts.on("-bp PARAMS_FILE.json", "--bench-params PARAMS_FILE.json", "Benchmark parameters JSON file") do |bp_file|
        raise "No such benchmark params file: #{bp_file.inspect}!" unless File.exist?(bp_file)
        bench_params_file = bp_file
    end

    opts.on("-dd DATA_DIR", "--data-dir DATA_DIR", "Location to write benchmark results, default: continuous_reporting/data") do |ddir|
        raise("No such directory: #{ddir.inspect}!") unless File.directory?(ddir)
        data_dir = ddir
    end

    opts.on("-v", "--verbose", "Print verbose output about tripwire checks") do
        is_verbose = true
    end
end.parse!

bench_params_data = bench_params_file ? JSON.parse(File.read bench_params_file) : {}

BENCHMARK_ARGS = benchmark_args || (bench_params_data["bench_type"] ? args_for_bench_type(bench_params_data["bench_type"]) : BENCH_TYPES["default"])
FULL_REBUILD = !full_rebuild.nil? ? full_rebuild : (bench_params_data["full_rebuild"] || false)
FILE_GH_ISSUE = should_file_gh_issue
ALL_PERF_TRIPWIRES = all_perf_tripwires
SINGLE_PERF_TRIPWIRE = single_perf_tripwire
VERBOSE = is_verbose
BENCH_PARAMS_FILE = bench_params_file
DATA_DIR = data_dir || bench_params_data["data_directory"] || "continuous_reporting/data"

PIDFILE = "/home/ubuntu/benchmark_ci.pid"

GITHUB_TOKEN=ENV["BENCHMARK_CI_GITHUB_TOKEN"]
if FILE_GH_ISSUE && !GITHUB_TOKEN
    raise "Set BENCHMARK_CI_GITHUB_TOKEN to an appropriate GitHub token to allow auto-filing issues! (or set --no-gh-issue)"
end

def ghapi_post(api_uri, params, verb: :post)
    uri = URI("https://api.github.com" + api_uri)

    req = Net::HTTP::Post.new(uri)
    #req.basic_auth GITHUB_USER, GITHUB_TOKEN
    req['Accept'] = "application/vnd.github.v3+json"
    req['Content-Type'] = "application/json"
    req['Authorization'] = "Bearer #{GITHUB_TOKEN}"
    req.body = JSON.dump(params)
    result = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    unless result.is_a?(Net::HTTPSuccess)
        $stderr.puts "Error in HTTP #{verb.upcase}: #{result.inspect}"
        $stderr.puts result.body
        $stderr.puts "------"
        raise "HTTP error when posting to #{api_uri}!"
    end

    JSON.load(result.body)
end

class BenchmarkDetails
    def initialize(timestamp)
        @timestamp = timestamp
        benchmark_details_file = File.join(BUILT_REPORTS_ROOT, "_benchmarks", "bench_#{timestamp}.md")
        @data = YAML.load File.read(benchmark_details_file)
    end

    def raw_data
        @data["test_results"]
    end

    def yjit_test_result
        yjit_file = @data["test_results"]["prod_ruby_with_yjit"]
        raise("Cannot locate latest YJIT data file for timestamp #{@timestamp}") unless yjit_file
        File.join RAW_BENCHMARK_ROOT, yjit_file
    end

    def yjit_permalink
        local_path = yjit_test_result
        relative_path = local_path.split("raw_benchmark_data", 2)[1]
        "https://speed.yjit.org/raw_benchmark_data/#{relative_path}"
    end
end

def escape_markdown(s)
    s.gsub(/(\*|\_|\`)/) { '\\' + $1 }.gsub("<", "&lt;")
end

def file_gh_issue(title, message)
    host = `uname -a`.chomp
    issue_body = <<~ISSUE
        Error running benchmark CI job on #{host}:

        #{message}
    ISSUE

    unless FILE_GH_ISSUE
        print "We would file a GitHub issue, but we were asked not to. Details:\n\n"

        print "==============================\n"
        print "Title: CI Benchmarking: #{title}\n"
        puts issue_body
        print "==============================\n"
        return
    end

    # Note: if you're set up as the GitHub user, it's not gonna email you since it thinks you filed it yourself.
    ghapi_post "/repos/Shopify/yjit-metrics/issues",
        {
            "title" => "CI Benchmarking: #{title}",
            "body" => issue_body
        }
end

if File.exist?(PIDFILE)
    pid = File.read(PIDFILE).to_i
    if pid && pid > 0
        ps_out = `pgrep -F #{PIDFILE}`
        if ps_out.include?(pid.to_s)
            raise "When trying to run benchmark_and_update.rb, the previous process (PID #{pid}) was still running!"
        end
    end
end
File.open(PIDFILE, "w") do |f|
    f.write Process.pid.to_s
end

def run_benchmarks
    return if BENCHMARK_ARGS.nil? || BENCHMARK_ARGS == ""

    # Run benchmarks from the top-level dir and write them into DATA_DIR
    Dir.chdir("#{__dir__}/..") do
        Dir["#{DATA_DIR}/*.json"].each do |f|
            FileUtils.rm f
        end

        args = "#{BENCHMARK_ARGS} --full-rebuild #{FULL_REBUILD ? "yes" : "no"}"
        YJITMetrics.check_call "#{RbConfig.ruby} basic_benchmark.rb #{args} --output=#{DATA_DIR}/ --bench-params=#{BENCH_PARAMS_FILE}"
    end
end

def report_and_upload
    Dir.chdir __dir__ do
        # This should copy the data directory into the directories for generating reports,
        # run any reports it needs to. We will tell it *not* to push to Git since we often won't have
        # GitHub tokens. The push can be done explicitly, later, not from this script.
        YJITMetrics.check_call "#{RbConfig.ruby} generate_and_upload_reports.rb -d data --no-push --no-report"

        # Delete the files from this run since they've now been processed.
        old_data_files = Dir["#{DATA_DIR}/*"].to_a
        unless old_data_files.empty?
            old_data_files.each { |f| FileUtils.rm f }
        end
    end
end

def clear_latest_data
    Dir.chdir __dir__ do
        old_data_files = Dir["#{DATA_DIR}/*"].to_a
        unless old_data_files.empty?
            old_data_files.each { |f| FileUtils.rm f }
        end
    end
end

def ts_from_tripwire_filename(filename)
    filename.split("blog_speed_details_")[1].split(".")[0]
end

def timestr_from_ts(ts)
    if ts =~ /\A(\d{4}-\d{2}-\d{2})-(\d{6})\Z/
        year_month_day = $1
        hour   = $2[0..1]
        minute = $2[2..3]
        second = $2[4..5]

        "#{year_month_day} #{hour}:#{minute}:#{second}"
    else
        raise "Could not parse timestamp: #{ts.inspect}"
    end
end

# If benchmark results drop noticeably, file a Github issue
def check_perf_tripwires
    Dir.chdir(YM_REPORT_DIR) do
        # Grab only non-platform-specific tripwire files that do *not* have a platform name in them,
        # but instead end in a six-digit timestamp.
        tripwire_files = Dir["*.tripwires.json"].to_a.select {|f| f =~ /\d{6}\.tripwires\.json\Z/}.sort

        if ALL_PERF_TRIPWIRES
            (tripwire_files.size - 1).times do |index|
                check_one_perf_tripwire(tripwire_files[index], tripwire_files[index - 1])
            end
        elsif SINGLE_PERF_TRIPWIRE
            specified_file = tripwire_files.detect { |f| f.include?(SINGLE_PERF_TRIPWIRE) }
            raise "Couldn't find perf tripwire report containing #{SINGLE_PERF_TRIPWIRE.inspect}!" unless specified_file

            specified_index = tripwire_files.index(specified_file)
            raise "Can't check perf on the very first report!" if specified_index == 0

            check_one_perf_tripwire(tripwire_files[specified_index], tripwire_files[specified_index - 1])
        else
            check_one_perf_tripwire(tripwire_files[-1], tripwire_files[-2])
        end
    end
end

def check_one_perf_tripwire(current_filename, compared_filename, verbose: VERBOSE)
    YJITMetrics::PLATFORMS.each do |platform|
        platform_current_filename = current_filename.gsub(".tripwires.json", ".#{platform}.tripwires.json")
    end

end

def check_one_perf_tripwire_file(current_filename, compared_filename, verbose: VERBOSE)
    current_data = JSON.parse File.read(current_filename)
    compared_data = JSON.parse File.read(compared_filename)

    check_failures = []

    compared_data.each do |bench_name, values|
        # Only compare if both sets of data have the benchmark
        next unless current_data[bench_name]

        current_mean = current_data[bench_name]["mean"]
        current_rsd_pct = current_data[bench_name]["rsd_pct"]
        compared_mean = values["mean"]
        compared_rsd_pct = values["rsd_pct"]

        current_stddev = (current_rsd_pct.to_f / 100.0) * current_mean
        compared_stddev = (compared_rsd_pct.to_f / 100.0) * compared_mean

        # Normally is_micro should be the same in all cases for any one specific benchmark.
        # So we just assume the most recent data has the correct value.
        is_micro = current_data[bench_name]["micro"]

        if is_micro
            bench_stddev_tolerance = MICRO_STDDEV_TOLERANCE
            bench_drop_tolerance = MICRO_DROP_TOLERANCE
        else
            bench_stddev_tolerance = NORMAL_STDDEV_TOLERANCE
            bench_drop_tolerance = NORMAL_DROP_TOLERANCE
        end

        # Occasionally stddev can change pretty wildly from run to run. Take the most tolerant of multiple-of-recent-stddev,
        # or a percentage of the larger mean runtime. Basically, a drop must be unusual enough (stddev) and large enough (mean)
        # for us to flag it.
        tolerance = [ current_stddev * bench_stddev_tolerance, compared_stddev * bench_stddev_tolerance,
            current_mean * bench_drop_tolerance, compared_mean * bench_drop_tolerance ].max

        drop = current_mean - compared_mean

        if verbose
            puts "#{is_micro ? "Microbenchmark" : "Benchmark"} #{bench_name}, tolerance is #{ "%.2f" % tolerance }, latest mean is #{ "%.2f" % current_mean } (stddev #{"%.2f" % current_stddev}), " +
                "next-latest mean is #{ "%.2f" % compared_mean } (stddev #{ "%.2f" % compared_stddev}), drop is #{ "%.2f" % drop }..."
        end

        if drop > tolerance
            puts "Benchmark #{bench_name} marked as failure!" if verbose
            check_failures.push({
                benchmark: bench_name,
                current_mean: current_mean,
                second_current_mean: compared_mean,
                current_stddev: current_stddev,
                current_rsd_pct: current_rsd_pct,
                second_current_stddev: compared_stddev,
                second_current_rsd_pct: compared_rsd_pct,
            })
        end
    end

    if check_failures.empty?
      puts "No benchmarks failing performance tripwire (#{current_filename})"
      return
    end

    puts "Failing benchmarks (#{current_filename}): #{check_failures.map { |h| h[:benchmark] }}"
    file_perf_bug(current_filename, compared_filename, check_failures)
end

def file_perf_bug(current_filename, compared_filename, check_failures)
    ts_latest = ts_from_tripwire_filename(current_filename)
    ts_penultimate = ts_from_tripwire_filename(compared_filename)

    # This expects to be called from the _includes/reports directory
    latest_yjit_results = BenchmarkDetails.new(ts_latest)
    latest_yjit_result_file = latest_yjit_results.yjit_test_result
    penultimate_yjit_results = BenchmarkDetails.new(ts_penultimate)
    penultimate_yjit_result_file = penultimate_yjit_results.yjit_test_result
    latest_yjit_data = JSON.parse File.read(latest_yjit_result_file)
    penultimate_yjit_data = JSON.parse File.read(penultimate_yjit_result_file)
    latest_yjit_ruby_desc = latest_yjit_data["ruby_metadata"]["RUBY_DESCRIPTION"]
    penultimate_yjit_ruby_desc = penultimate_yjit_data["ruby_metadata"]["RUBY_DESCRIPTION"]

    failing_benchmarks = check_failures.map { |h| h[:benchmark] }

    puts "Filing Github issue - slower benchmark(s) found."
    body = <<~BODY_TOP
    Latest failing benchmark:

    * Time: #{timestr_from_ts(ts_latest)}
    * Ruby: #{escape_markdown latest_yjit_ruby_desc}
    * [Raw YJIT prod data](#{latest_yjit_results.yjit_permalink})

    Compared to previous benchmark:

    * Time: #{timestr_from_ts(ts_penultimate)}
    * Ruby: #{escape_markdown penultimate_yjit_ruby_desc}
    * [Raw YJIT prod data](#{penultimate_yjit_results.yjit_permalink})

    Slower benchmarks: #{failing_benchmarks.join(", ")}

    [Timeline Graph](https://speed.yjit.org/timeline-deep##{failing_benchmarks.join("+")})

    Slowdown details:

    BODY_TOP

    check_failures.each do |bench_hash|
        # Indentation with here-docs is hard - use the old-style with extremely literal whitespace handling.
        body += <<ONE_BENCH_REPORT
* #{bench_hash[:benchmark]}:
    * Speed before: #{"%.2f" % bench_hash[:second_current_mean]} +/- #{"%.1f" % bench_hash[:second_current_rsd_pct]}%
    * Speed after: #{"%.2f" % bench_hash[:current_mean]} +/- #{"%.1f" % bench_hash[:current_rsd_pct]}%
ONE_BENCH_REPORT
    end

    file_gh_issue("Benchmark at #{ts_latest} is significantly slower than the one before (#{ts_penultimate})!", body)
end

begin
    run_benchmarks
rescue
    host = `uname -a`.chomp
    puts $!.full_message
    raise "Exception in CI benchmarks: #{$!.message}!"
end

# There's no error if this isn't here, but it's cleaner to remove it.
FileUtils.rm PIDFILE
