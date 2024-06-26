# frozen_string_literal: true
require_relative "./memory_details_report"
require_relative "./speed_details_multi_platform_report"

module YJITMetrics
  class MemoryDetailsMultiPlatformReport < SpeedDetailsMultiPlatformReport
    def self.report_name
        "blog_memory_details"
    end

    def self.single_report_class
      ::YJITMetrics::MemoryDetailsReport
    end
  end
end
