#!/usr/bin/env ruby

require "json"
require "optparse"
require_relative "lib/yjit-metrics"

report_class_by_name = YJITMetrics::TimelineReport.report_name_hash
# By sorting, we make sure that the first report name that returns true from .start_with? is the "real" match.
all_report_names = report_class_by_name.keys.sort

# Default settings
data_dir = "data"
output_dir = "."

# Default benchmarks and configs to compare
configs = [ "prod_ruby_no_jit", "prod_ruby_with_yjit", "ruby_30_with_mjit" ]
benchmarks = [ "railsbench", "optcarrot", "liquid-render", "activerecord" ]
reports = all_report_names.dup

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: timeline_report.rb [options]
    BANNER

    opts.on("-d DIR", "--dir DIR", "Read data files from this directory") do |dir|
        data_dir = dir
    end

    opts.on("-o DIR", "--output-dir DIR", "Directory for writing output files (default: current dir)") do |dir|
        output_dir = dir
    end

    opts.on("-b BENCH_NAMES", "--benchmarks BENCH_NAMES", "Benchmarks to include or to make visible by default") do |bench|
        benchmarks = bench.split(",")
    end

    opts.on("-r REPORTS", "--reports REPORTS", "Run these reports on the data (known reports: #{all_report_names.join(", ")})") do |str|
        report_strings = str.split(",")

        # Just as OptionParser lets us abbreviate long arg names, we'll let the user abbreviate report names.
        reports = report_strings.map { |report_string| all_report_names.detect { |name| name.start_with?(report_string) } }
        bad_indices = reports.map.with_index { |entry, idx| entry.nil? ? idx : nil }.compact
        raise("Unknown reports: #{bad_indices.map { |idx| report_strings[idx] }.inspect}! Known report types are: #{all_report_names.join(", ")}") unless bad_indices.empty?
    end
end.parse!

# Expand relative paths *before* we change into the data directory
output_dir = File.expand_path(output_dir)

DATASET_FILENAME_RE = /^(\d{4}-\d{2}-\d{2}-\d{6})_basic_benchmark_(\d{4}_)?(.*).json$/
DATASET_FILEPATH_RE = /^(.*\/)?(\d{4}-\d{2}-\d{2}-\d{6})_basic_benchmark_(\d{4}_)?(.*).json$/
# Return the information from the file path - run_num is nil if the file isn't in multi-run format
def parse_dataset_filepath(filepath)
    filename = filepath.split("/")[-1]
    unless filename =~ DATASET_FILENAME_RE
        raise "Internal error! Filename #{filename.inspect} doesn't match expected naming of data files!"
    end
    config_name = $3
    run_num = $2 ? $2.chomp("_") : $2
    timestamp = ts_string_to_date($1)
    return [ filepath, config_name, timestamp, run_num ]
end

def ts_string_to_date(ts)
    year, month, day, hms = ts.split("-")
    hour, minute, second = hms[0..1], hms[2..3], hms[4..5]
    DateTime.new year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i, second.to_i
end

def ruby_desc_to_sha(ruby_desc)
  return $1 if ruby_desc =~ / ([a-z0-9]{10})\)/

  raise "Could not extract Git SHA from RUBY_DESCRIPTION: #{ruby_desc.inspect}"
end

Dir.chdir(data_dir)

files_in_dir = Dir["**/*"].grep(DATASET_FILEPATH_RE)
relevant_results = files_in_dir.map { |filepath| parse_dataset_filepath(filepath) }

if relevant_results.size == 0
    puts "No relevant data files found for directory #{data_dir.inspect} and specified arguments!"
    exit -1
end

latest_ts = relevant_results.map { |_, _, timestamp, _| timestamp }.max
puts "Loading #{relevant_results.size} data files..."

result_set_by_ts = {}
filepaths_by_ts = {}
ruby_desc_by_ts = {}
relevant_results.each do |filepath, config_name, timestamp, run_num|
    benchmark_data = JSON.load(File.read(filepath))
    filepaths_by_ts[timestamp] ||= []
    filepaths_by_ts[timestamp].push filepath  # Is this used? I'm not sure this is used.
    if config_name == "prod_ruby_with_yjit"
        ruby_desc_by_ts[timestamp] = ruby_desc_to_sha benchmark_data["ruby_metadata"]["RUBY_DESCRIPTION"]
    end
    begin
        result_set_by_ts[timestamp] ||= YJITMetrics::ResultSet.new
        result_set_by_ts[timestamp].add_for_config(config_name, benchmark_data)
    rescue
        puts "Error adding data from #{filepath.inspect}!"
        raise
    end
end

configs = relevant_results.map { |_, config_name, _, _| config_name }.uniq.sort
all_timestamps = result_set_by_ts.keys.sort
stats_timestamps = relevant_results.flat_map { |_, config_name, timestamp, _| config_name == "yjit_stats" ? [timestamp] : [] }

# This should match the JS parser in the template files
TIME_FORMAT = "%Y %m %d %H %M %S"

# Grab a statistical summary of every timestamp, config and benchmark
summary_by_ts = {}
all_benchmarks = []
all_timestamps.each do |ts|
    summary_by_ts[ts] = result_set_by_ts[ts].summary_by_config_and_benchmark
    all_benchmarks += summary_by_ts[ts].values.flat_map(&:keys)
end
all_benchmarks.uniq!
all_benchmarks.sort!

benchmarks = benchmarks & all_benchmarks

context = {
    result_set_by_timestamp: result_set_by_ts,
    summary_by_timestamp: summary_by_ts,
    ruby_desc_by_timestamp: ruby_desc_by_ts,

    configs: configs,
    timestamps: all_timestamps,
    timestamps_with_stats: stats_timestamps,

    selected_benchmarks: benchmarks,
    benchmark_order: all_benchmarks,
}

reports.each do |report_name|
    report = report_class_by_name[report_name].new context
    report.write_file(output_dir + "/#{report_name}")
end
