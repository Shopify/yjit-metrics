# frozen_string_literal: true

require_relative "../report"

# We'd like to be able to create a quick columnar report, often for one
# Ruby config versus another, and load/dump it as JSON or CSV. This isn't a
# report class that is all things to all people -- it's specifically
# a comparison of two or more configurations per-benchmark for yjit-bench.
#
# The first configuration given is assumed to be the baseline against
# which the other configs are measured.
module YJITMetrics
  class PerBenchRubyComparisonRepor < Report
    def self.report_name
      "per_bench_compare"
    end

    def initialize(config_names, results, benchmarks: [])
      super

      @headings = [ "bench" ] + config_names.flat_map { |config| [ "#{config}", "RSD" ] } + alt_configs.map { |config| "#{config}/#{base_config}" }
      @col_formats = [ "%s" ] + config_names.flat_map { [ "%.1fms", "%.1f%%" ] } + alt_configs.map { "%.2f" }

      @report_data = []
      times_by_config = {}
      config_names.each { |config| times_by_config[config] = results.times_for_config_by_benchmark(config) }

      benchmark_names = times_by_config[config_names[0]].keys

      times_by_config.each do |config_name, results|
        raise("No results for configuration #{config_name.inspect} in PerBenchRubyComparison!") if results.nil?
      end

      benchmark_names.each do |benchmark_name|
        # Only run benchmarks if there is no list of "only run these" benchmarks, or if the benchmark name starts with one of the list elements
        unless @only_benchmarks.empty?
          next unless @only_benchmarks.any? { |bench_spec| benchmark_name.start_with?(bench_spec) }
        end
        row = [ benchmark_name ]
        config_names.each do |config|
          unless times_by_config[config][benchmark_name]
            raise("Configuration #{config.inspect} has no results for #{benchmark_name.inspect} even though #{config_names[0]} does in the same dataset!")
          end
          config_times = times_by_config[config][benchmark_name]
          config_mean = mean(config_times)
          row.push config_mean
          row.push 100.0 * stddev(config_times) / config_mean
        end

        base_config_mean = mean(times_by_config[base_config][benchmark_name])
        alt_configs.each do |config|
          config_mean = mean(times_by_config[config][benchmark_name])
          row.push config_mean / base_config_mean
        end

        @report_data.push row
      end
    end

    def base_config
      @config_names[0]
    end

    def alt_configs
      @config_names[1..-1]
    end

    def to_s
      format_as_table(@headings, @col_formats, @report_data) + config_legend_text
    end

    def config_legend_text
      [
        "",
        "Legend:",
        alt_configs.map do |config|
          "- #{config}/#{base_config}: ratio of mean(#{config} times)/mean(#{base_config} times). >1 means #{base_config} is faster."
        end,
        "RSD is relative standard deviation (percent).",
        ""
      ].join("\n")
    end
  end
end
