#!/usr/bin/env ruby

require "json"
require "optparse"
require_relative "lib/yjit-metrics"

RESULT_SET = YJITMetrics::ResultSet.new
REPORT_OBJ_BY_NAME = {
    "per_bench_compare" => proc { |config_names:, benchmarks: []|
        STDERR.puts "Config_names: #{config_names.inspect}"
        YJITMetrics::PerBenchRubyComparison.new(config_names, RESULT_SET, benchmarks: benchmarks)
    },
    "yjit_stats_default" => proc { |config_names:, benchmarks: []|
        YJITMetrics::YJITStatsExitReport.new(config_names, RESULT_SET, benchmarks: benchmarks)
    },
    "yjit_stats_multi" => proc { |config_names:, benchmarks: []|
        YJITMetrics::YJITStatsMultiRubyReport.new(config_names, RESULT_SET, benchmarks: benchmarks)
    },
}
REPORT_NAMES = REPORT_OBJ_BY_NAME.keys

# Default settings
use_all_in_dir = false
reports = [ "per_bench_compare" ]
data_dir = "data"
only_benchmarks = []  # Empty list means use all benchmarks present in the data files

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: basic_report.rb [options] [<filenames>]
        Reports available: per_bench_ruby_compare, yjit_stats_default
        If no files are specified, report on all results that have the latest timestamp.
    BANNER

    opts.on("--all", "Use all files in the directory, not just latest or arguments") do
        use_all_in_dir = true
    end

    opts.on("--reports=REPORTS", "Run these reports on the data (known reports: #{REPORT_NAMES.join(", ")})") do |str|
        reports = str.split(",")
        bad_names = reports - REPORT_NAMES
        raise("Unknown reports: #{bad_names.inspect}! Known report types are: #{REPORT_NAMES.join(", ")}") unless bad_names.empty?
    end

    opts.on("--benchmarks=BENCHNAMES", "Report only for benchmarks with names that match this/these comma-separated strings") do |benchnames|
        only_benchmarks = benchnames.split(",")
    end

    opts.on("-d DIR", "--dir DIR", "Read data files from this directory") do |dir|
        data_dir = dir
    end
end.parse!

DATASET_FILENAME_RE = /^(\d{4}-\d{2}-\d{2}-\d{6})_basic_benchmark_(.*).json$/

def ts_string_to_date(ts)
    year, month, day, hms = ts.split("-")
    hour, minute, second = hms[0..1], hms[2..3], hms[4..5]
    DateTime.new year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i, second.to_i
end

Dir.chdir(data_dir)

files_in_dir = Dir["*"].grep(DATASET_FILENAME_RE)
file_data = files_in_dir.map do |filename|
    unless filename =~ DATASET_FILENAME_RE
        raise "Internal error! Filename #{filename.inspect} doesn't match expected naming of data files!"
    end
    config_name = $2
    timestamp = ts_string_to_date($1)
    [ filename, config_name, timestamp ]
end

if use_all_in_dir
    unless ARGV.empty?
        raise "Don't use --all with specified filenames!"
    end
    relevant_results = file_data
else
    if ARGV.empty?
        # No args? Use latest set of results
        latest_ts = file_data.map { |_, _, timestamp| timestamp }.max

        relevant_results = file_data.select { |_, _, timestamp| timestamp == latest_ts }
    else
        # One or more named files? Use that set of timestamps.
        timestamps = ARGV.map do |filepath|
            filename = filepath.split("/")[-1]
            unless filename =~ DATASET_FILENAME_RE
                raise "Error! Filename #{filename.inspect} doesn't match expected naming of data files!"
            end
            timestamp = ts_string_to_date($2)
        end
        timestamps.uniq!
        relevant_results = file_data.select { |_, _, timestamp| timestamps.include?(timestamp) }
    end
end

if relevant_results.size == 0
    puts "No relevant data files found for directory #{data_dir.inspect} and specified arguments!"
    exit -1
end

puts "Loading #{relevant_results.size} data files..."

relevant_results.each do |filename, config_name, timestamp|
    benchmark_data = JSON.load(File.read(filename))
    begin
        RESULT_SET.add_for_config(config_name, benchmark_data)
    rescue
        puts "Error adding data from #{filename.inspect}!"
        raise
    end
end

config_names = relevant_results.map { |filename, config_name, timestamp| config_name }.uniq

reports.each do |report_name|
    report = REPORT_OBJ_BY_NAME[report_name].call(config_names: config_names, benchmarks: only_benchmarks)

    if report.respond_to?(:write_file)
        timestamp = Time.now.getgm.strftime('%F-%H%M%S')

        report.write_file("#{report_name}_#{timestamp}")
    end

    print report.to_s
    puts
end
