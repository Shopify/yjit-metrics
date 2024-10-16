#!/usr/bin/env ruby

require "open3"
require "optparse"
require "json"

# Determine benchmarking parameters so that the same values can be passed to each server.
# The relevant JSON file parameters are:
#
# Timestamp: this is the timestamp on which the run begins. File output uses this in
# the name to indicate that all relevant files are part of the same benchmarking run
# with the same configuration(s).
#
# Full rebuild: a "real" benchmarking pass will delete all relevant Rubies and
# installed gems, do a "make clean" and "git clean" on the CRuby source repo
# and generally try to get about as clean a build as possible. This is time-consuming,
# and can be skipped for (e.g.) smoke-test runs.
#
# CRuby name: this is the CRuby branch or SHA being tested.
#
# CRuby repo: this is the repo that contains the branch or SHA for CRuby.
#
# CRuby SHA: If a branch name is given (e.g. master) this script will record the
# variable-over-time name, but also the specific SHA tested. If CRuby_name is a
# SHA then this SHA should match it. Note that SHA is an output based on name, it's
# not an input (though the name can be a SHA.)
#
# YJIT-Bench Name, Repo and SHA: like with CRuby, a branch or short SHA can be given for
# the name, and the SHA will be recorded too.
#
# YJIT-Metrics Name, Repo and SHA: same as CRuby name and SHA, but for yjit-metrics.
#
# Data directory: normal "mainstream" builds will be recorded under the "raw_benchmarks"
# data directory, to be included in the normal CRuby timeline reports. Smoke-test
# data will normally be written to a temp directory or thrown away and not recorded
# anywhere, and so not have a normal data directory. Other builds (e.g. speculative
# speed-testing of an unmerged branch) may want to record data to a different location.

full_rebuild = true
out_file = "bench_params.json"
output_ts = Time.now.getgm.strftime('%F-%H%M%S')
bench_type = "default"
cruby_name = "master"
cruby_repo = "https://github.com/ruby/ruby"
yjit_metrics_name = "main"
yjit_metrics_repo = "https://github.com/Shopify/yjit-metrics.git"
yjit_bench_name = "main"
yjit_bench_repo = "https://github.com/Shopify/yjit-bench.git"
benchmark_data_dir = nil

def non_empty(s)
  s = s.to_s.strip
  s unless s.empty?
end

def string_to_bool(s)
  return true if s.match?(/^(true|1|yes)$/i)
  return false if s.match?(/^(false|0|no)$/i)
  fail "Expected boolean got #{s.inspect}"
end

OptionParser.new do |opts|
  opts.banner = <<~BANNER
    Usage: #{File.basename($0)} [options]
  BANNER

  opts.on("--full-rebuild YN") do |fr|
    full_rebuild = string_to_bool(fr)
  end

  opts.on("--output-timestamp TS") do |ts|
    ts = ts.strip
    if !ts.empty?
      if !ts.match?(/^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$/)
        raise ArgumentError, "Timestamp should match YYYY-mm-dd-HHMMSS"
      end
      output_ts = ts
    end
  end

  opts.on("--bench-type BT") do |bt|
    bench_type = bt
  end

  opts.on("--yjit-metrics-name YM") do |ym|
    non_empty(ym)&.then { yjit_metrics_name = _1 }
  end

  opts.on("--yjit-metrics-repo YMR") do |ymr|
    yjit_metrics_repo = ymr
  end

  opts.on("--yjit-bench-name YB") do |yb|
    non_empty(yb)&.then { yjit_bench_name = _1 }
  end

  opts.on("--yjit-bench-repo YBR") do |ybr|
    yjit_bench_repo = ybr
  end

  opts.on("--cruby-name NAME") do |name|
    non_empty(name)&.then { cruby_name = _1 }
  end

  opts.on("--cruby-repo NAME") do |repo|
    non_empty(repo)&.then { cruby_repo = _1 }
  end

  opts.on("--benchmark-data-dir PATH") do |dir|
    raise "--benchmark-data-dir must specify a directory" if dir.to_s.empty?
    benchmark_data_dir = dir
  end
end.parse!

raise "--benchmark-data-dir is required!" unless benchmark_data_dir

def sha_like?(s)
  s&.match?(/\A\h{6,}\Z/) # At least 6 hex chars, all hex chars
end

def sha_exists?(repo, name)
  return false unless repo.start_with?("https://github.com")

  require "uri"
  require "net/https"

  uri = URI(repo.delete_suffix(".git"))
  Net::HTTP.start(uri.hostname, use_ssl: true) do |http|
    http.head("#{uri.path}/commits/#{name}").code.to_i == 200
  end
end

def sha_for_repo(name:, repo:)
  stdout, status = Open3.capture2("git", "ls-remote", repo, name)

  if status.success?
    sha = stdout.split(/\s/).first.to_s
    return sha if sha_like?(sha)
  end

  return name if sha_like?(name) && sha_exists?(repo, name)

  raise("Error trying to find SHA for name #{name.inspect} repo #{repo.inspect}!")
end

yjit_metrics_sha = sha_for_repo name: yjit_metrics_name, repo: yjit_metrics_repo
yjit_bench_sha = sha_for_repo name: yjit_bench_name, repo: yjit_bench_repo
cruby_sha = sha_for_repo name: cruby_name, repo: cruby_repo

output = {
  ts: output_ts,
  full_rebuild: full_rebuild,
  bench_type: bench_type,
  cruby_name: cruby_name,
  cruby_sha: cruby_sha,
  cruby_repo: cruby_repo,
  yjit_bench_name: yjit_bench_name,
  yjit_bench_sha: yjit_bench_sha,
  yjit_bench_repo: yjit_bench_repo,
  yjit_metrics_name: yjit_metrics_name,
  yjit_metrics_sha: yjit_metrics_sha,
  yjit_metrics_repo: yjit_metrics_repo,
  data_directory: benchmark_data_dir,
}

puts "Writing file: #{out_file}..."
File.open(out_file, "w") { |f| f.write JSON.pretty_generate(output) }
