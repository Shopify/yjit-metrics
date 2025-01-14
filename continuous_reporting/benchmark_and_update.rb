#!/usr/bin/env ruby

require_relative "../lib/yjit_metrics"

require 'fileutils'
require 'net/http'

require "yaml"
require "optparse"
require 'rbconfig'

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
        "--min-bench-time=30.0 --min-bench-itrs=10") +
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
end.parse!

bench_params_data = bench_params_file ? JSON.parse(File.read bench_params_file) : {}

BENCHMARK_ARGS = benchmark_args || (bench_params_data["bench_type"] ? args_for_bench_type(bench_params_data["bench_type"]) : BENCH_TYPES["default"])
FULL_REBUILD = !full_rebuild.nil? ? full_rebuild : (bench_params_data["full_rebuild"] || false)
BENCH_PARAMS_FILE = bench_params_file
DATA_DIR = File.expand_path(data_dir || bench_params_data["data_directory"] || "continuous_reporting/data")

PIDFILE = "/home/ubuntu/benchmark_ci.pid"

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

begin
    run_benchmarks
rescue
    puts $!.full_message
    raise "Exception in CI benchmarks: #{$!.message}!"
end

# There's no error if this isn't here, but it's cleaner to remove it.
FileUtils.rm PIDFILE
