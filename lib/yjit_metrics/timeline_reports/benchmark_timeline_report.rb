# frozen_string_literal: true

require_relative "../timeline_report"

module YJITMetrics
  class BenchmarkTimelineReport < TimelineReport
    def self.report_name
      "benchmark_timeline"
    end

    CONFIG_NAMES = {
      "prev_ruby_no_jit" => "CRUBY stable",
      "prev_ruby_yjit" => "YJIT stable",
      "prod_ruby_no_jit" => "CRUBY dev",
      "prod_ruby_with_yjit" => "YJIT dev",
      "zjit_prod" => "ZJIT dev",
    }
  end
end
