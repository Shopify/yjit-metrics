#!/usr/bin/env ruby

require "json"
require "yaml"
require "fileutils"
require "optparse"

require_relative "../lib/yjit-metrics"

# Raw benchmark data gets written to a platform- and date-specific subdirectory, but will often be read from multiple subdirectories.
RAW_BENCHMARK_ROOT = "raw_benchmark_data"

def benchmark_file_out_path(filename)
    if filename =~ /^(.*)_basic_benchmark_(.*).json$/
        ts = $1
        config = $2

        config_platform = YJITMetrics::PLATFORMS.detect { |platform| config.start_with?(platform) }
        if !config_platform
            raise "Can't parse platform from config in filename: #{filename.inspect} / #{config.inspect}!"
        end

        year, month, day, tm = ts.split("-")
        if ts == "" || year == "" || day == ""
            raise "Empty string when parsing timestamp: #{ts.inspect}!"
        end
        "#{RAW_BENCHMARK_ROOT}/#{config_platform}/#{year}-#{month}/#{ts}_basic_benchmark_#{config}.json"
    else
        raise "Can't parse filename: #{filename}!"
    end
end

copy_from = []

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: file_benchmark_data_into_raw.rb [options]
        Specify directories with -d to add new test results and reports.
    BANNER

    opts.on("-d DIR", "Copy raw data and report files out of this directory (may be specified multiple times)") do |dir|
        copy_from << dir
    end
end.parse!

if copy_from.empty?
    puts "No directories to copy. Success!"
end

# If want to check into the repo and file issues, we need credentials.
YJIT_METRICS_PAGES_DIR = File.expand_path File.join(__dir__, "../../yjit-metrics-pages")

unless File.exist?(YJIT_METRICS_PAGES_DIR)
    raise "This script expects to be cloned in a repo right next to a \"yjit-metrics-pages\" repo of the `pages` branch of yjit-metrics"
end

# Copy JSON and report files into the branch
copy_from.each do |dir_to_copy|
    Dir.chdir(dir_to_copy) do
        # Copy raw data files to a place we can link them rather than include them in pages
        Dir["*_basic_benchmark_*.json"].each do |filename|
            out_file = benchmark_file_out_path(filename)
            dir = File.join(YJIT_METRICS_PAGES_DIR, File.dirname(out_file))
            FileUtils.mkdir_p dir
            FileUtils.cp(filename, File.join(YJIT_METRICS_PAGES_DIR, out_file))
            puts "Copying data file: #{filename.inspect} to #{out_file.inspect} in dir #{dir.inspect}"
            # If the copy succeeded, we can delete it locally
            FileUtils.rm filename
        end
    end
end

# From here on out, we're just in the yjit-metrics checkout of "pages"
Dir.chdir(YJIT_METRICS_PAGES_DIR)

puts "Copied benchmark data into place successfully!"
