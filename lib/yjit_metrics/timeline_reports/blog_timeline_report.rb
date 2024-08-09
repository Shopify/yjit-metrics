# frozen_string_literal: true

require_relative "../timeline_report"

module YJITMetrics
  class BlogTimelineReport < TimelineReport
    def self.report_name
      "blog_timeline"
    end

    CONFIG_NAMES = {
      "prod_ruby_with_yjit" => "yjit",
    }
  end
end
