#!/usr/bin/env ruby

require "json"
require "yaml"
require "fileutils"
require "optparse"

require_relative "../lib/yjit-metrics"

YJIT_RAW_DATA_REPO = File.expand_path File.join(__dir__, "../../raw-benchmark-data/raw_benchmark_data")

DESTINATIONS = [
    YJIT_RAW_DATA_REPO,
]

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
        "#{config_platform}/#{year}-#{month}/#{ts}_basic_benchmark_#{config}.json"
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

# Copy JSON and report files into the branch
copy_from.each do |dir_to_copy|
    Dir.chdir(dir_to_copy) do
        # Copy raw data files to a place we can link them rather than include them in pages
        Dir["*_basic_benchmark_*.json"].each do |filename|
            DESTINATIONS.each do |dest|
                out_path = benchmark_file_out_path(filename)
                dir = File.join(dest, File.dirname(out_path))
                FileUtils.mkdir_p dir
                FileUtils.cp(filename, File.join(dest, out_path))
                puts "Copying data file: #{filename.inspect} to #{dest.inspect} / #{out_path.inspect} in dir #{dir.inspect}"
            end
            # If the copy succeeded, we can delete it locally
            FileUtils.rm filename
        end
    end
end

puts "Copied benchmark data into place successfully!"
