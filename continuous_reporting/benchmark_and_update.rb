#!/usr/bin/env ruby

require_relative "../lib/yjit-metrics"

require 'net/http'

# This is intended to be the top-level script for running benchmarks, reporting on them
# and uploading the results. It belongs in a cron job with some kind of error detection
# to make sure it's running properly.

# We want to run our benchmarks, then update GitHub Pages appropriately.

OUTPUT_LOG = "/home/ubuntu/benchmark_ci_output.txt"

GITHUB_USER=ENV["YJIT_METRICS_GITHUB_USER"]
GITHUB_TOKEN=ENV["YJIT_METRICS_GITHUB_TOKEN"]
unless GITHUB_USER && GITHUB_TOKEN
    raise "Set YJIT_METRICS_GITHUB_USER and YJIT_METRICS_GITHUB_TOKEN to an appropriate GitHub username/token for repo access and opening issues!"
end

def run_benchmarks
    # Run benchmarks from the top-level dir and write them into continuous_reporting/data
    Dir.chdir("#{__dir__}/..") do
        old_data_files = Dir["continuous_reporting/data/*"].to_a
        unless old_data_files.empty?
            old_data_files.each { |f| FileUtils.rm f }
        end

        # This is a much faster set of tests, more suitable for quick testing
        #YJITMetrics.check_call "ruby basic_benchmark.rb --warmup-itrs=10 --min-bench-time=0.01 --min-bench-itrs=50 --on-errors=re_run --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit --output=continuous_reporting/data/ activerecord respond_to fib getivar lee"

        # TODO: turn on Truffle?
        YJITMetrics.check_call "ruby basic_benchmark.rb --warmup-itrs=100 --min-bench-time=0.01 --min-bench-itrs=500 --runs=3 --on-errors=re_run --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit --output=continuous_reporting/data/"
    end
end

def report_and_upload
    Dir.chdir __dir__ do
        # This runs reports and uploads the results
        YJITMetrics.check_call "ruby generate_and_upload_reports.rb -d data"

        old_data_files = Dir["continuous_reporting/data/*"].to_a
        unless old_data_files.empty?
            old_data_files.each { |f| FileUtils.rm f }
        end
    end
end

def ghapi_post(api_uri, params, verb: :post)
    uri = URI("https://api.github.com" + api_uri)

    req = Net::HTTP::Post.new(uri)
    req.basic_auth GITHUB_USER, GITHUB_TOKEN
    req['Accept'] = "application/vnd.github.v3+json"
    req['Content-Type'] = "application/json"
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

begin
    run_benchmarks
    report_and_upload
rescue
    exc = $!

    # If not attached to a tty, stdout often won't flush promptly.
    # We'd like to include as much output as practical.
    $stdout.flush

    logged_output = File.read(OUTPUT_LOG) if File.exist?(OUTPUT_LOG)

    host = `uname -a`
    issue_body = <<~ISSUE
        <pre>
        While running CI benchmarks on #{host.inspect}
        benchmark_and_update.rb encountered an exception:

        ======
        #{exc.full_message}
        ======

        Including contents of #{OUTPUT_LOG} if present:

        #{logged_output}

        </pre>
    ISSUE

    # And if this fails... Well, then it fails. We did what we could.
    ghapi_post "/repos/Shopify/yjit-metrics/issues",
        {
            "title" => "YJIT-Metrics CI Benchmarking failure!",
            "body" => issue_body,
            "assignees" => [ "noahgibbs" ]
        }
end
