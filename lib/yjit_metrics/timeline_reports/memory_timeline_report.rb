# frozen_string_literal: true

require_relative "../timeline_report"

module YJITMetrics
  class MemoryTimelineReport < TimelineReport
    def self.report_name
      "memory_timeline"
    end

    CONFIG_NAMES = {
      "prod_ruby_no_jit" => "no-jit",
      "prod_ruby_with_yjit" => "yjit",
    }

    def build_row(ts, this_point, this_ruby_desc)
      # These fields are from the ResultSet summary - peak_mem_bytes is an array because multiple runs are possible
      [ ts, this_point["peak_mem_bytes"].max, this_ruby_desc ]
    end
  end
end
