#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require "optparse"
require_relative "../lib/metrics_app"

DEFAULT_CONFIGS = %w[
  yjit_stats
  zjit_stats
  prod_ruby_with_yjit
  prod_ruby_zjit
  prod_ruby_no_jit
  prev_ruby_yjit
  prev_ruby_no_jit
].map { |config| "#{MetricsApp::PLATFORM}_#{config}" }

bench_params_file = ENV["BENCH_PARAMS"]
cli_full_rebuild = nil
cli_configs = nil

OptionParser.new do |opts|
  opts.banner = "Usage: install_rubies.rb [options]"

  opts.on("--bench-params=FILE", "Benchmark parameters JSON file") do |file|
    bench_params_file = file
  end

  opts.on("--configs=CONFIGS", "Comma-separated list of configs to install") do |configs|
    cli_configs = configs.split(",").map(&:strip)
      .map { |s| s.gsub("PLATFORM", MetricsApp::PLATFORM) }
  end

  opts.on("--full-rebuild=YN", "Whether to fully rebuild all rubies") do |fr|
    cli_full_rebuild = fr.nil? || fr.strip == "" || fr.match?(/^(true|1|yes)$/i)
  end
end.parse!

bench_data = {}
timestamp = nil

if bench_params_file && File.exist?(bench_params_file)
  bench_data = JSON.parse(File.read(bench_params_file))
  ts = bench_data["ts"]
  unless ts =~ /\A\d{4}-\d{2}-\d{2}-\d{6}\Z/
    raise "Bad format for given timestamp: #{ts.inspect}!"
  end
  timestamp = ts
end

# Command-line options override bench_params, which override defaults
full_rebuild = if !cli_full_rebuild.nil?
  cli_full_rebuild
elsif bench_data.key?("full_rebuild")
  bench_data["full_rebuild"]
else
  false
end

configs_to_install = cli_configs || DEFAULT_CONFIGS

overrides = {}
if bench_data["cruby_repo"] || bench_data["cruby_sha"]
  overrides[:cruby] = {
    git_url: bench_data["cruby_repo"],
    git_branch: bench_data["cruby_sha"],
  }.compact
end

puts "install_rubies.rb:"
puts "  configs: #{configs_to_install.inspect}"
puts "  full_rebuild: #{full_rebuild.inspect}"
puts "  overrides: #{overrides.inspect}"

MetricsApp::Rubies.install_all!(
  configs_to_install,
  rebuild: full_rebuild,
  overrides: overrides.empty? ? nil : overrides,
)

prod_yjit_config = "#{MetricsApp::PLATFORM}_prod_ruby_with_yjit"
if configs_to_install.include?(prod_yjit_config)
  ruby_path = MetricsApp::Rubies.ruby(prod_yjit_config)
  puts "BENCHMARK_RUBY_PATH=#{ruby_path}"
end

if timestamp
  date = timestamp.split("-")[0..2].join
  puts "BENCHMARK_DATE=#{date}"
end
