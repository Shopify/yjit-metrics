#!/usr/bin/env ruby

require "optparse"
require "json"

require_relative "../lib/yjit-metrics"

# A particular run through the benchmarking system has a number of important parameters.
# Most, though not all, are captured in the JSON file produced here. In general,
# params should be captured here if the Ruby benchmarking or reporting process
# needs to know their value, and not captured here if the parameter can be entirely
# handled via Jenkins (e.g. what Slack user or channel to notify on benchmarking failure.)
#
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
#

YJIT_METRICS_DIR = File.expand_path("..", __dir__)
YJIT_BENCH_DIR = File.expand_path("../yjit-bench", YJIT_METRICS_DIR)
CRUBY_DIR = File.expand_path("../prod-yjit", YJIT_METRICS_DIR)

full_rebuild = true
out_file = "bench_params.json"
output_ts = Time.now.getgm.strftime('%F-%H%M%S')
bench_type = "default"
cruby_name = "master"
cruby_repo = "https://github.com/ruby/ruby"
yjit_metrics_name = "main"
yjit_metrics_repo = ""
yjit_bench_name = "main"
yjit_bench_repo = "https://github.com/Shopify/yjit-bench.git"
benchmark_data_dir = nil

# TODO: try looking up the given yjit_metrics and/or yjit_bench and/or CRuby revisions in the local repos to see if they exist?

OptionParser.new do |opts|
  opts.banner = <<~BANNER
    Usage: create_json_params_file.rb [options]
  BANNER

  opts.on("-fr YN", "--full-rebuild YN") do |fr|
    full_rebuild = YJITMetrics::CLI.human_string_to_boolean(fr)
  end

  opts.on("-ot TS", "--output-timestamp TS") do |ts|
    output_ts = ts
  end

  opts.on("-bt BT", "--bench-type BT") do |bt|
    bench_type = bt
  end

  opts.on("-ym YM", "--yjit-metrics-name YM") do |ym|
    # Blank yjit_metrics rev? Use main.
    ym = "main" if ym.nil? || ym.strip == ""
    yjit_metrics_name = ym
  end

  opts.on("-ymr YMR", "--yjit-metrics-repo YMR") do |ymr|
    yjit_metrics_repo = ymr
  end

  opts.on("-yb YB", "--yjit-bench-name YB") do |yb|
    # Blank yjit_bench rev? Use main.
    yb = "main" if yb.nil? || yb.strip == ""
    yjit_bench_name = yb
  end

  opts.on("-ybr YBR", "--yjit-bench-repo YBR") do |ybr|
    yjit_bench_repo = ybr
  end

  opts.on("-cn NAME", "--cruby-name NAME") do |name|
    name == "master" if name.nil? || name.strip == ""
    cruby_name = name.strip
  end

  opts.on("-cr NAME", "--cruby-repo NAME") do |repo|
    cruby_repo = repo.strip
  end

  opts.on("-bd PATH", "--benchmark-data-dir PATH") do |dir|
    raise "--benchmark-data-dir must specify a directory" if dir.to_s.empty?
    benchmark_data_dir = File.expand_path(dir)
  end
end.parse!

raise "--benchmark-data-dir is required!" unless benchmark_data_dir

def sha_for_name_in_dir(name:, dir:, repo:, desc:)
  Dir.chdir(dir) do
    system("git remote remove current_repo") # Don't care if this succeeds or not
    system("git remote add current_repo #{repo}")
    system("git fetch current_repo") || raise("Error trying to fetch latest revisions for #{desc}!")

    out = `git log -n 1 --pretty=oneline current_repo/#{name}`
    unless out && out.strip != ""
      # The git log above did nothing useful... Is it already a SHA?
      out = `git log -n 1 --pretty=oneline #{name}`

      if name.strip =~ /\A[a-zA-Z0-9]{6,}\Z/ # At least 6 hex chars, all hex chars
        return name.strip
      end
      raise("Error trying to find SHA for #{dir.inspect} name #{name.inspect} repo #{repo.inspect}!")
    end

    sha = out.split(" ")[0]
    raise("Output doesn't start with SHA: #{out.inspect}!") unless sha && sha =~ /\A[0-9a-zA-Z]{8}/
    return sha
  end
end

yjit_metrics_sha = sha_for_name_in_dir name: yjit_metrics_name, dir: YJIT_METRICS_DIR, repo: yjit_metrics_repo, desc: "yjit_metrics"
yjit_bench_sha = sha_for_name_in_dir name: yjit_bench_name, dir: YJIT_BENCH_DIR, repo: yjit_bench_repo, desc: "yjit_bench"
cruby_sha = sha_for_name_in_dir name: cruby_name, dir: CRUBY_DIR, repo: cruby_repo, desc: "Ruby"

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
