# frozen_string_literal: true

require_relative "../timeline_report"

module YJITMetrics
  class MiniTimelinesReport < TimelineReport
    def self.report_name
      "mini_timelines"
    end

    def build_series!
      config = find_config("prod_ruby_with_yjit")
      platform = platform_of_config(config)

      # This should match the JS parser in the template file
      time_format = "%Y %m %d %H %M %S"

      @series = []

      @context[:selected_benchmarks].each do |benchmark|
        points = @context[:timestamps].map do |ts|
          this_point = @context[:summary_by_timestamp].dig(ts, config, benchmark)
          if this_point
            this_ruby_desc = @context[:ruby_desc_by_config_and_timestamp][config][ts] || "unknown"
            # These fields are from the ResultSet summary
            [ ts.strftime(time_format), this_point["mean"], this_ruby_desc ]
          else
            nil
          end
        end
        points.compact!
        next if points.empty?

        @series.push({
          config: config,
          benchmark: benchmark,
          name: "#{config}-#{benchmark}",
          platform: platform,
          data: points,
        })
      end

      #@series.sort_by! { |s| s[:name] }
    end

    def write_files(out_dir)
      script_template = ERB.new File.read(__dir__ + "/../report_templates/mini_timeline_d3_template.html.erb")
      html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
      File.open("#{out_dir}/_includes/reports/mini_timelines.html", "w") { |f| f.write(html_output) }
    end
  end
end
