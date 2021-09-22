#!/usr/bin/env ruby

require "json"
require "optparse"
require_relative "lib/yjit-metrics"

all_report_names = [ "blog_timeline" ]

# Default settings
data_dir = "data"
output_dir = "."

# Default benchmarks and configs to compare
configs = [ "prod_ruby_no_jit", "prod_ruby_with_yjit", "ruby_30_with_mjit" ]
benchmarks = [ "railsbench", "optcarrot", "lee", "activerecord" ]
reports = all_report_names

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

# Not currently used
CONFIGS_TO_HUMAN_NAMES = {
    "prod_ruby_no_jit" => "No JIT",
    "prod_ruby_with_yjit" => "YJIT",
    "ruby_30_with_mjit" => "MJIT",
    "truffleruby" => "Truffle",
}

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

# For now we have a single timeline report type and we hardcode it here.
if reports.include?("blog_timeline")
    report_name = "blog_timeline"
    @series = []
    config = "prod_ruby_with_yjit"
    ALL_BENCHMARKS.each do |benchmark|
        all_points = ALL_TIMESTAMPS.map do |ts|
            this_point = summary_by_ts.dig(ts, config, benchmark)
            if this_point
                # These fields are from the ResultSet summary
                [ ts.strftime("%Y %m %d %H %M %S"), this_point["mean"], this_point["stddev"] ]
            else
                nil
            end
        end

        visible = benchmarks.include?(benchmark)

        @series.push({ config: config, benchmark: benchmark, name: "#{config}-#{benchmark}", visible: visible, data: all_points.compact })
    end
    @series.sort_by! { |s| s[:visible] ? 0 : 1 }

    script_template = ERB.new File.read(__dir__ + "/lib/yjit-metrics/report_templates/blog_timeline_d3_template.html.erb")
    html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
    File.open(output_dir + "/#{report_name}.html", "w") { |f| f.write(html_output) }
end
