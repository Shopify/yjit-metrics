class BlogTimelineReport < YJITMetrics::TimelineReport
    def self.report_name
        "blog_timeline"
    end

    def initialize(context)
        super

        config = "prod_ruby_with_yjit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = []

        @context[:benchmark_order].each do |benchmark|
            all_points = @context[:all_timestamps].map do |ts|
                this_point = @context[:summary_by_timestamp].dig(ts, config, benchmark)
                if this_point
                    # These fields are from the ResultSet summary
                    [ ts.strftime(time_format), this_point["mean"], this_point["stddev"] ]
                else
                    nil
                end
            end

            visible = @context[:selected_benchmarks].include?(benchmark)

            @series.push({ config: config, benchmark: benchmark, name: "#{config}-#{benchmark}", visible: visible, data: all_points.compact })
        end
        @series.sort_by! { |s| s[:visible] ? 0 : 1 }
    end

    def write_file(file_path)
        script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_timeline_d3_template.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(output_dir + "/#{report_name}.html", "w") { |f| f.write(html_output) }
    end
end

class MiniTimelinesReport < YJITMetrics::TimelineReport
    def self.report_name
        "mini_timelines"
    end

    def initialize(context)
        super

        config = "prod_ruby_with_yjit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = []

        @context[:selected_benchmarks].each do |benchmark|
            all_points = @context[:all_timestamps].map do |ts|
                this_point = @context[:summary_by_timestamp].dig(ts, config, benchmark)
                if this_point
                    # These fields are from the ResultSet summary
                    [ ts.strftime(time_format), this_point["mean"] ]
                else
                    nil
                end
            end

            @series.push({ config: config, benchmark: benchmark, name: "#{config}-#{benchmark}", data: all_points.compact })
        end
    end

    def write_file(file_path)
        script_template = ERB.new File.read(__dir__ + "/../report_templates/mini_timeline_d3_template.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(output_dir + "/#{report_name}.html", "w") { |f| f.write(html_output) }
    end
end
