#!/usr/bin/env ruby

require_relative "../lib/yjit-metrics"

require 'fileutils'
require 'net/http'

require "optparse"

# This is intended to be the top-level script for running benchmarks, reporting on them
# and uploading the results. It belongs in a cron job with some kind of error detection
# to make sure it's running properly.

# We want to run our benchmarks, then update GitHub Pages appropriately.

# Remember that if this is running on the benchmark CI server you do *not* want a run so long it will
# overlap with the regular automatic runs. They happen twice daily as I write this, at 7am and 7pm.
# Configurations should be a subset of: yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit,truffleruby
BENCH_TYPES = {
    "none"       => nil,
    "default"    => "--warmup-itrs=10  --min-bench-time=20.0  --min-bench-itrs=10   --on-errors=re_run --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit",
    "minimal"    => "--warmup-itrs=1   --min-bench-time=10.0  --min-bench-itrs=5    --on-errors=re_run --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit activerecord lee 30k_methods",
    "extended"   => "--warmup-itrs=500 --min-bench-time=120.0 --min-bench-itrs=1000 --runs=3 --on-errors=re_run --configs=yjit_stats,prod_ruby_no_jit,ruby_30_with_mjit,prod_ruby_with_yjit,truffleruby",
}
benchmark_args = BENCH_TYPES["default"]

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: benchmark_and_update.rb [options]

        Example benchmark args: "#{BENCH_TYPES["default"]}"
    BANNER

    opts.on("-b BENCHTYPE", "--benchmark-type BENCHTYPE", "The type of benchmarks to run - give a basic_benchmark.rb command line, or one of: #{BENCH_TYPES.keys.inspect}") do |btype|
      if btype.include?("-") # If it has a dash, we assume it's arguments for basic_benchmark
        benchmark_args = btype
      elsif BENCH_TYPES.has_key?(btype)
        benchmark_args = BENCH_TYPES[btype]
      else
        raise "Unrecognized benchmark args or type: #{btype.inspect}! Known types: #{BENCH_TYPES.keys.inspect}"
      end
    end
end.parse!

BENCHMARK_ARGS = benchmark_args

PIDFILE = "/home/ubuntu/benchmark_ci.pid"

GITHUB_USER=ENV["YJIT_METRICS_GITHUB_USER"]
GITHUB_TOKEN=ENV["YJIT_METRICS_GITHUB_TOKEN"]
unless GITHUB_USER && GITHUB_TOKEN
    raise "Set YJIT_METRICS_GITHUB_USER and YJIT_METRICS_GITHUB_TOKEN to an appropriate GitHub username/token for repo access and opening issues!"
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

def file_gh_issue(title, message)
    host = `uname -a`.chomp
    issue_body = <<~ISSUE
        <pre>
        Error running benchmark CI job on #{host}:

        #{message}
        </pre>
    ISSUE

    ghapi_post "/repos/Shopify/yjit-metrics/issues",
        {
            "title" => "YJIT-Metrics CI Benchmarking: #{title}",
            "body" => issue_body,
            "assignees" => [ GITHUB_USER ]
        }
end

if File.exist?(PIDFILE)
    pid = File.read(PIDFILE).to_i
    if pid && pid > 0
        ps_out = `ps -p #{pid}`
        if ps_out.include?(pid.to_s)
            raise "When trying to run benchmark_and_update.rb, the previous process (PID #{pid}) was still running!"
        end
    end
end
File.open(PIDFILE, "w") do |f|
    f.write Process.pid.to_s
end

def run_benchmarks
    return if BENCHMARK_ARGS.nil?

    # Run benchmarks from the top-level dir and write them into continuous_reporting/data
    Dir.chdir("#{__dir__}/..") do
        old_data_files = Dir["continuous_reporting/data/*"].to_a
        unless old_data_files.empty?
            old_data_files.each { |f| FileUtils.rm f }
        end

        # This is a much faster set of tests, more suitable for quick testing
        YJITMetrics.check_call "ruby basic_benchmark.rb #{BENCHMARK_ARGS} --output=continuous_reporting/data/"
    end
end

def report_and_upload
    Dir.chdir __dir__ do
        # This should copy the data directory into the Jekyll directories,
        # run any reports it needs to and check the results into Git.
        YJITMetrics.check_call "ruby generate_and_upload_reports.rb -d data"

        old_data_files = Dir["continuous_reporting/data/*"].to_a
        unless old_data_files.empty?
            old_data_files.each { |f| FileUtils.rm f }
        end
    end
end

def clear_latest_data
    Dir.chdir __dir__ do
        old_data_files = Dir["continuous_reporting/data/*"].to_a
        unless old_data_files.empty?
            old_data_files.each { |f| FileUtils.rm f }
        end
    end
end

def ts_from_tripwire_filename(filename)
    filename.split("blog_speed_details")[1].split(".")[0]
end

# If something starts getting false positives, we'll ignore it. Example bad benchmark: jekyll
EXCLUDE_HIGH_NOISE_BENCHMARKS = [ "jekyll" ]

# If benchmark results drop noticeably, file a Github issue
def check_perf_tripwires
    Dir.chdir(__dir__ + "/../../yjit-metrics-pages/_includes/reports") do
        tripwire_files = Dir["*.tripwires.json"].to_a.sort

        latest = tripwire_files[-1]
        penultimate = tripwire_files[-2]

        latest_data = JSON.parse File.read(latest)
        penultimate_data = JSON.parse File.read(penultimate)

        check_failures = []

        penultimate_data.each do |bench_name, values|
            # Only compare if both sets of data have the benchmark
            next unless latest_data[bench_name]
            next if EXCLUDE_HIGH_NOISE_BENCHMARKS.include?(bench_name)

            latest_mean = latest_data[bench_name]["mean"]
            latest_rsd_pct = latest_data[bench_name]["rsd_pct"]
            penultimate_mean = values["mean"]
            penultimate_rsd_pct = values["rsd_pct"]

            latest_stddev = (latest_rsd_pct.to_f / 100.0) * latest_mean
            penultimate_stddev = (penultimate_rsd_pct.to_f / 100.0) * penultimate_mean

            # Occasionally stddev can change pretty wildly from run to run. Take the most tolerant of 2x recent stddev,
            # or 5% of the larger mean runtime.
            tolerance = [ latest_stddev * 2.0, penultimate_stddev * 2.0, latest_mean * 0.05, penultimate_mean * 0.05 ].max

            drop = latest_mean - penultimate_mean

            puts "Benchmark #{bench_name}, tolerance is #{ "%.2f" % tolerance }, latest mean is #{ "%.2f" % latest_mean }, next-latest mean is #{ "%.2f" % penultimate_mean }, drop is #{ "%.2f" % drop }..."

            if drop > tolerance
                puts "Benchmark #{bench_name} marked as failure!"
                check_failures.push({
                    benchmark: bench_name,
                    latest_mean: latest_mean,
                    second_latest_mean: penultimate_mean,
                    latest_stddev: latest_stddev,
                    latest_rsd_pct: latest_rsd_pct,
                    second_latest_stddev: penultimate_stddev,
                    second_latest_rsd_pct: penultimate_rsd_pct,
                })
            end
        end

        if check_failures.empty?
          puts "No benchmarks failing performance tripwire - yay!"
          return
        end

        ts_latest = ts_from_tripwire_filename(latest)
        ts_penultimate = ts_from_tripwire_filename(penultimate)

        body = <<~BODY
        Latest failing benchmark: #{latest}
        Compared to previous benchmark: #{penultimate}

        Failing benchmark names: #{check_failures.map { |h| h[:benchmark] }.inspect}

        <pre>
        Failure details:

        #{JSON.pretty_generate check_failures}
        </pre>
        BODY
        file_gh_issue("Benchmark at #{ts_latest} is significantly slower than the one before!", body)
    end
end

begin
    run_benchmarks
    report_and_upload
    check_perf_tripwires
    clear_latest_data
rescue
    host = `uname -a`.chomp
    puts $!.full_message
    raise "Exception in CI benchmarks: #{$!.message}!"
end

# There's no error if this isn't here, but it's cleaner to remove it.
FileUtils.rm PIDFILE
