#!/usr/bin/env ruby

require "json"
require "optparse"
require_relative "../lib/yjit-metrics"

report_class_by_name = YJITMetrics::Report.report_name_hash
# By sorting, we make sure that the first report name that returns true from .start_with? is the "real" match.
all_report_names = report_class_by_name.keys.sort

# Default settings
data_dir = "data"
output_dir = "."

# Default benchmarks and configs to compare
configs = [ "prod_ruby_no_jit", "prod_ruby_with_yjit", "ruby_30_with_mjit" ]
benchmarks = [ "railsbench", "optcarrot", "lee", "activerecord" ]

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
relevant_results = files_in_dir.map { |filename| parse_dataset_filename(filename) }

if relevant_results.size == 0
    puts "No relevant data files found for directory #{data_dir.inspect} and specified arguments!"
    exit -1
end

latest_ts = relevant_results.map { |_, _, timestamp, _| timestamp }.max
puts "Loading #{relevant_results.size} data files..."

result_set_by_ts = {}
filenames_by_ts = {}
relevant_results.each do |filename, config_name, timestamp, run_num|
    benchmark_data = JSON.load(File.read(filename))
    filenames_by_ts[timestamp] ||= []
    filenames_by_ts[timestamp].push filename
    begin
        result_set_by_ts[timestamp] ||= YJITMetrics::ResultSet.new
        result_set_by_ts[timestamp].add_for_config(config_name, benchmark_data)
    rescue
        puts "Error adding data from #{filename.inspect}!"
        raise
    end
end

ALL_CONFIGS = relevant_results.map { |_, config_name, _, _| config_name }.uniq
ALL_TIMESTAMPS = result_set_by_ts.keys.sort

summary_by_ts = {}
all_benchmarks = []
ALL_TIMESTAMPS.each do |ts|
    summary_by_ts[ts] = result_set_by_ts[ts].summary_by_config_and_benchmark
    all_benchmarks += summary_by_ts[ts].values.flat_map(&:keys)
end
all_benchmarks.uniq!
ALL_BENCHMARKS = all_benchmarks

benchmarks = benchmarks & ALL_BENCHMARKS

#puts "Configs: #{ALL_CONFIGS.inspect}"
#puts "Benchmarks: #{benchmarks.inspect}"
#puts "Timestamps: #{ALL_TIMESTAMPS.inspect}"

#ALL_TIMESTAMPS.each do |ts|
#    ALL_CONFIGS.each do |config|
#        ALL_BENCHMARKS.each do |benchmark|
#            next unless [ "railsbench" ].include?(benchmark)
#            # Grab the datapoint if the datapoint exists for this combination
#            single_summary = summary_by_ts.dig(ts, config, benchmark)
#            mean = single_summary["mean"]
#        end
#    end
#end

@series = []
configs.each do |config|
    benchmarks.each do |benchmark|
        all_points = ALL_TIMESTAMPS.map do |ts|
            this_point = summary_by_ts.dig(ts, config, benchmark)
            if this_point
                [ ts.to_time.to_f, this_point["mean"] ]  # this_point["stddev"]
            else
                nil
            end
        end

        @series.push({ name: "#{config}-#{benchmark}", data: all_points.compact })
    end
end

script_template = ERB.new File.read(__dir__ + "/timeline_graph_rickshaw_template.html.erb")
html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
File.open(output_dir + "/timeline_report.html", "w") { |f| f.write(html_output) }
