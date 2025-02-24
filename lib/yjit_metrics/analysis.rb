# frozen_string_literal: true

require "json"

# Parse recent result json files and analyze various metrics.
# Currently includes identifying streaks in ratio_in_yjit and detecting regressions.

module YJITMetrics
  module Analysis
    REPORT_LINK = "[Analysis Report](https://speed.yjit.org/analysis.txt)"

    # Build report by reading files from provided dir.
    # Load results from the last #{count} benchmark runs.
    def self.report_from_dir(dir, benchmarks: nil, count: 30, before: nil)
      metrics = self.metrics
      # We only need to load the files for the following configs ("yjit_stats"...).
      configs = metrics.map(&:config).uniq

      # data = {yjit_stats: {"x86_64_yjit_stats" => [result_hash, ...], ...}
      data = configs.each_with_object({}) do |config, h|
        YJITMetrics::PLATFORMS.each do |platform|
          files = Dir.glob("**/*_basic_benchmark_#{platform}_#{config}.json", base: dir).sort
          if before
            files = files.reject { |f| f.match(/(\d{4}-\d{2}-\d{2})/)[1] >= before }
          end
          files = files.last(count).map { |f| File.join(dir, f) }

          runs = files.map { |f| JSON.parse(File.read(f)) }.group_by { |x| x["ruby_config_name"] }
          # Append data to h[:yjit_stats]["x86_64_yjit_stats"].
          (h[config] ||= {}).merge!(runs) { |k, oldv, newv| oldv + newv }
        end
      end

      report_from_data(data, metrics:, benchmarks:)
    end

    # Build report from hash of data (built by `report_from_dir`).
    def self.report_from_data(data, metrics: self.metrics, benchmarks: nil)
      # {ratio_in_yjit: {"x86_64_yjit_stats" => {"benchmark_name" => results_of_check, ...}}
      metrics.each_with_object({}) do |metric, h|
        data[metric.config].each_pair do |config_name, run|
          metric.report(run, benchmarks:).then do |result|
            # h[:ratio_in_yjit]["x86_64_yjit_stats"] = ...
            (h[metric.name] ||= {})[config_name] = result unless result.empty?
          end
        end
      end.then do |results|
        Report.new(results)
      end
    end

    def self.metrics
      Metric.subclasses.map(&:new)
    end

    class Report
      attr_reader :results

      def initialize(results)
        @results = results
      end

      # Format regression data into a notification message.
      def regression_notification
        msg = Hash.new { |h, k| h[k] = [] }

        results.each_pair do |metric, h|
          h.each_pair do |platform, values|
            values.sort.each do |benchmark, report|
              next unless regression = report[:regression]

              msg["#{metric} #{platform}"] << "- `#{benchmark}` regression: #{regression}"
            end
          end
        end

        return if msg.empty?

        lines = msg.sort.flatten
        lines << REPORT_LINK
        lines.join("\n")
      end
    end

    class Metric
      include Stats

      def config
        self.class::CONFIG
      end

      def name
        self.class::NAME
      end
    end

    class RatioInYJIT < Metric
      # Subclass configuration.
      CONFIG = :yjit_stats
      NAME = :ratio_in_yjit

      # Class internal constants.
      ROUND_DIGITS = 2
      # Consider last X vals to identify regressions and reduce false positives.
      VALS_TO_CONSIDER = 2

      def report(results, benchmarks: nil)
        # These nested values come from the json files and the keys are strings.
        config = self.config.to_s
        name = self.name.to_s

        # Transform [{"yjit_stats" => {"benchmark" => [[stats_hash]]}}]
        # into {"benchmark" => [stat_value, ...]}.
        values = results.each_with_object({}) do |run, h|
          run[config].each_pair do |benchmark, data|
            (h[benchmark] ||= []) << data.dig(0, 0, name)
          end
        end

        regressions = {}
        values.each_pair do |benchmark, vals|
          # Allow limiting report to specific benchmarks.
          next if benchmarks && !benchmarks.include?(benchmark)

          check_values(vals)&.then do |val|
            regressions[benchmark] = val
          end
        end

        regressions
      end

      # Check the list of values for one benchmark.
      # Returns either nil or string description of regression.
      # vals are percentages * 100 (99.6970...).
      def check_values(vals)
        # [1,1,2,2,2,3] => [ [1, 2], [2, 3], [3, 1] ]
        streaks = vals.map { |f| f.round(ROUND_DIGITS) }.chunk { _1 }.map { |x,xs| [x, xs.size] }

        curr = vals[-1]
        calculation_vals = vals[0..(-1 - VALS_TO_CONSIDER)]

        if !calculation_vals.empty?
          min = calculation_vals.min
          mean = self.mean(calculation_vals)
          stddev = self.stddev(calculation_vals)

          # Notify if the last X vals are below the threshold.
          threshold = (min - stddev * 0.5)
          regression = if vals.last(VALS_TO_CONSIDER).all? { _1 < threshold }
            sprintf "%.*f is %.*f%% below mean %.*f",
              ROUND_DIGITS, curr,
              ROUND_DIGITS, (mean - curr) / mean * 100,
              ROUND_DIGITS, mean
          end
        end

        {
          streaks:,
          highest_streak_value: streaks.select { _2 > 1 }.map(&:first)&.max,
          longest_streak: streaks.select { _2 > 1 }.max_by { _2 },
          mean:,
          stddev:,
          regression:,
        }.compact
      end
    end
  end
end
