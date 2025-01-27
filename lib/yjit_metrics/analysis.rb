# frozen_string_literal: true

require "json"

# Parse recent result json files and analyze various metrics.
# Currently includes identifying streaks in ratio_in_yjit and detecting regressions.

module YJITMetrics
  module Analysis
    REPORT_LINK = "[Analysis Report](https://speed.yjit.org/analysis.txt)"

    # Build report by reading files from provided dir.
    def self.report_from_dir(dir)
      metrics = self.metrics
      count = metrics.map(&:count).max
      configs = metrics.map(&:config).uniq

      # data = {"yjit_stats" => {"x86_64_yjit_stats" => [result_hash, ...], ...}
      data = configs.each_with_object({}) do |config, h|
        YJITMetrics::PLATFORMS.each do |platform|
          files = Dir.glob("**/*_basic_benchmark_#{platform}_#{config}.json", base: dir).sort.last(count).map { |f| File.join(dir, f) }

          runs = files.map { |f| JSON.parse(File.read(f)) }.group_by { |x| x["ruby_config_name"] }
          (h[config] ||= {}).merge!(runs) { |k, oldv, newv| oldv + newv }
        end
      end

      report_from_data(data, metrics:)
    end

    # Build report from hash of data (built by `report_from_dir`).
    def self.report_from_data(data, metrics: self.metrics)
      # {ratio_in_yjit: {"x86_64_yjit_stats" => {"benchmark_name" => results_of_check, ...}}
      metrics.each_with_object({}) do |metric, h|
        data[metric.config].each_pair do |config_name, run|
          metric.check(run).then do |result|
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
          h.each_pair do |platform, vs|
            vs.sort.each do |benchmark, report|
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

      def count
        self.class::COUNT
      end

      def name
        self.class::NAME
      end
    end

    class RatioInYJIT < Metric
      CONFIG = :yjit_stats
      COUNT = 30
      NAME = :ratio_in_yjit
      ROUND = 2
      TOLERANCE = 0.1

      def check(results, benchmarks: nil)
        values = results.each_with_object({}) do |run, h|
          run["yjit_stats"].each_pair do |benchmark, data|
            (h[benchmark] ||= []) << data.dig(0, 0, "ratio_in_yjit")
          end
        end

        regressions = {}
        values.each_pair do |benchmark, vals|
          next if benchmarks && !benchmarks.include?(benchmark)

          check_one(vals)&.then do |val|
            regressions[benchmark] = val
          end
        end

        regressions
      end

      # Check the list of values for one benchmark.
      # Returns either nil or string description of regression.
      def check_one(vals)
        # vals are percentages * 100 (99.6970...).
        vals = vals.map { |f| f.round(ROUND) }
        high_streak = nil
        regression = nil
        (1...vals.size).each do |i|
          prev, curr = vals.values_at(i-1, i)

          delta = curr - prev

          if delta.abs <= TOLERANCE
            high_streak = curr if !high_streak || high_streak < curr
          end

          if high_streak
            delta = curr - high_streak

            regression = if delta < -TOLERANCE
              diff_pct = 0 - delta / high_streak * 100
              sprintf "dropped %.*f%% from %.*f to %.*f", ROUND, diff_pct, ROUND, high_streak, ROUND, curr
            end
          end
        end

        # [1,1,2,2,2,3] => [ [1, 2], [2, 3], [3, 1] ]
        streaks = vals.chunk { _1 }.map { |x,xs| [x, xs.size] }
        {
          #summary: streaks.map { |x,s| s == 1 ? x : "#{x} (x#{s})" }.join(", "),
          streaks:,
          highest_streak_value: streaks.select { _2 > 1 }.map(&:first)&.max,
          longest_streak: streaks.select { _2 > 1 }.max_by { _2 },
          geomean: geomean(vals),
          regression:,
        }.compact
      end
    end
  end
end
