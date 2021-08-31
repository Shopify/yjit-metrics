#!/usr/bin/env ruby

require_relative "../lib/yjit-metrics"

# This is intended to be the top-level script for running benchmarks, reporting on them
# and uploading the results. It belongs in a cron job with some kind of error detection
# to make sure it's running properly.

# We want to run our benchmarks, then update GitHub Pages appropriately.

# TODO: would this be happier as a shellscript rather than Ruby?

# Run benchmarks from the top-level dir and write them into continuous_reporting/data
Dir.chdir("#{__dir__}/..") do
    old_data_files = Dir["continuous_reporting/data/*"].to_a
    unless old_data_files.empty?
        old_data_files.each { |f| FileUtils.rm f }
    end
    #YJITMetrics.check_call "ruby basic_benchmark.rb --warmup-itrs=100 --min-bench-time=0.01 --min-bench-itrs=500 --runs=3 --on-errors=re_run --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit --output=continuous_reporting/data/"

    # This is a much faster set of tests; TODO: switch to the slow, complete tests
    YJITMetrics.check_call "ruby basic_benchmark.rb --warmup-itrs=10 --min-bench-time=0.01 --min-bench-itrs=50 --on-errors=re_run --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit --output=continuous_reporting/data/ activerecord respond_to fib getivar lee"
end

Dir.chdir __dir__ do
    # This runs reports and uploads the results
    YJITMetrics.check_call "ruby generate_and_upload_reports.rb -d data"

    old_data_files = Dir["continuous_reporting/data/*"].to_a
    unless old_data_files.empty?
        old_data_files.each { |f| FileUtils.rm f }
    end
end
