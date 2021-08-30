#!/usr/bin/env ruby

require "json"
require "optparse"
require_relative "lib/yjit-metrics"

RESULT_SET = YJITMetrics::ResultSet.new

report_class_by_name = YJITMetrics::Report.report_name_hash
# By sorting, we make sure that the first report name that returns true from .start_with? is the "real" match.
all_report_names = report_class_by_name.keys.sort

# Default settings
use_all_in_dir = false
reports = [ "per_bench_compare" ]
data_dir = "data"
output_dir = "."
write_output_files = false
only_benchmarks = []  # Empty list means use all benchmarks present in the data files

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: basic_report.rb [options] [<filenames>]
        Reports available: #{all_report_names.join(", ")}
        If no files are specified, report on all results that have the latest timestamp.
    BANNER

    opts.on("--all", "Use all files in the directory, not just latest or arguments") do
        use_all_in_dir = true
    end

    opts.on("--reports=REPORTS", "Run these reports on the data (known reports: #{all_report_names.join(", ")})") do |str|
        report_strings = str.split(",")

        # Just as OptionParser lets us abbreviate long arg names, we'll let the user abbreviate report names.
        reports = report_strings.map { |report_string| all_report_names.detect { |name| name.start_with?(report_string) } }
        bad_indices = reports.map.with_index { |entry, idx| entry.nil? ? idx : nil }.compact
        raise("Unknown reports: #{bad_indices.map { |idx| report_strings[idx] }.inspect}! Known report types are: #{all_report_names.join(", ")}") unless bad_indices.empty?
    end

    opts.on("--benchmarks=BENCHNAMES", "Report only for benchmarks with names that match this/these comma-separated string(s)") do |benchnames|
        only_benchmarks = benchnames.split(",")
    end

    opts.on("-d DIR", "--dir DIR", "Read data files from this directory") do |dir|
        data_dir = dir
    end

    opts.on("-o DIR", "--output-dir DIR", "Directory for writing output files (default: current dir)") do |dir|
        output_dir = dir
    end

    opts.on("-w", "--write-files", "Write out files, including HTML and CSV files, if supported by report type") do
        write_output_files = true
    end
end.parse!

# Expand relative paths *before* we change into the data directory
output_dir = File.expand_path(output_dir)

DATASET_FILENAME_RE = /^(\d{4}-\d{2}-\d{2}-\d{6})_basic_benchmark_(\d{4}_)?(.*).json$/
# Return the information from the filename - run_num is nil if the file isn't in multi-run format
def parse_dataset_filename(filename)
    filename = filename.split("/")[-1]
    unless filename =~ DATASET_FILENAME_RE
        raise "Internal error! Filename #{filename.inspect} doesn't match expected naming of data files!"
    end
    config_name = $3
    run_num = $2 ? $2.chomp("_") : $2
    timestamp = ts_string_to_date($1)
    return [ filename, config_name, timestamp, run_num ]
end

def ts_string_to_date(ts)
    year, month, day, hms = ts.split("-")
    hour, minute, second = hms[0..1], hms[2..3], hms[4..5]
    DateTime.new year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i, second.to_i
end

Dir.chdir(data_dir)

files_in_dir = Dir["*"].grep(DATASET_FILENAME_RE)
file_data = files_in_dir.map { |filename| parse_dataset_filename(filename) }

if use_all_in_dir
    unless ARGV.empty?
        raise "Don't use --all with specified filenames!"
    end
    relevant_results = file_data
else
    if ARGV.empty?
        # No args? Use latest set of results
        latest_ts = file_data.map { |_, _, timestamp, _| timestamp }.max

        relevant_results = file_data.select { |_, _, timestamp, _| timestamp == latest_ts }
    else
        # One or more named files? Use that set of timestamps.
        timestamps = ARGV.map { |filepath| parse_dataset_filename(filepath)[2] }.uniq
        relevant_results = file_data.select { |_, _, timestamp, _| timestamps.include?(timestamp) }
    end
end

if relevant_results.size == 0
    puts "No relevant data files found for directory #{data_dir.inspect} and specified arguments!"
    exit -1
end

puts "Loading #{relevant_results.size} data files..."

relevant_results.each do |filename, config_name, timestamp, run_num|
    benchmark_data = JSON.load(File.read(filename))
    begin
        RESULT_SET.add_for_config(config_name, benchmark_data)
    rescue
        puts "Error adding data from #{filename.inspect}!"
        raise
    end
end

config_names = relevant_results.map { |_, config_name, _, _| config_name }.uniq

reports.each do |report_name|
    report_type = report_class_by_name[report_name]
    report = report_type.new(config_names, RESULT_SET, benchmarks: only_benchmarks)

    if write_output_files && report.respond_to?(:write_file)
        timestamp = Time.now.getgm.strftime('%F-%H%M%S')

        report.write_file("#{output_dir}/#{report_name}_#{timestamp}")
    end

    print report.to_s
    puts
end
