# frozen_string_literal: true

require_relative "../report"
require_relative "./speed_details_report"

module YJITMetrics
  class SpeedDetailsMultiPlatformReport < Report
    def self.report_name
      "blog_speed_details"
    end

    def self.single_report_class
      ::YJITMetrics::SpeedDetailsReport
    end

    # Report-extensions tries to be data-agnostic. That doesn't work very well here.
    # It turns out that the platforms in the result set determine a lot of the
    # files we generate. So we approximate by generating (sometimes-empty) indicator
    # files. That way we still rebuild all the platform-specific files if they have
    # been removed or a new type is added.
    def self.report_extensions
      single_report_class.report_extensions
    end

    def initialize(config_names, results, benchmarks: [])
      # We need to instantiate N sub-reports for N platforms
      @platforms = results.platforms
      @sub_reports = {}
      @platforms.each do |platform|
        platform_config_names = config_names.select { |name| name.start_with?(platform) }

        # If we can't find a config with stats for this platform, is there one in x86_64?
        unless platform_config_names.detect { |config| config.include?("yjit_stats") }
          x86_stats_config = config_names.detect { |config| config.start_with?("x86_64") && config.include?("yjit_stats") }
          puts "Can't find #{platform} stats config, falling back to using x86_64 stats"
          platform_config_names << x86_stats_config if x86_stats_config
        end

        raise("Can't find a stats config for this platform in #{config_names.inspect}!") if platform_config_names.empty?
        @sub_reports[platform] = self.class.single_report_class.new(platform_config_names, results, platform: platform, benchmarks: benchmarks)
        if @sub_reports[platform].inactive
          puts "Platform config names: #{platform_config_names.inspect}"
          puts "All config names: #{config_names.inspect}"
          raise "Unable to produce stats-capable report for platform #{platform.inspect} in SpeedDetailsMultiplatformReport!"
        end
      end
    end

    def write_file(filename)
      # First, write out per-platform reports
      @sub_reports.values.each do |report|
        # Each sub-report will add the platform name for itself
        report.write_file(filename)
      end

      # extensions:

      # For each of these types, we'll just include for each platform and we can switch display
      # in the site. They exist, but there's no combined multiplatform version.
      # We'll create an empty 'tracker' file for the combined version.
      self.class.report_extensions.each do |ext|
        outfile = "#{filename}.#{ext}"
        File.open(outfile, "w") { |f| f.write("") }
      end
    end
  end
end
