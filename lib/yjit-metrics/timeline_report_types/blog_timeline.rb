class BlogTimelineReport < YJITMetrics::TimelineReport
    def self.report_name
        "blog_timeline"
    end

    def initialize(context)
        super

        config_x86 = "x86_64_prod_ruby_with_yjit"
        config_arm = "aarch64_prod_ruby_with_yjit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = []

        @context[:benchmark_order].each do |benchmark|
            [config_x86, config_arm].each do |config|
                points = @context[:timestamps].map do |ts|
                    this_point = @context[:summary_by_timestamp].dig(ts, config, benchmark)
                    if this_point
                        this_ruby_desc = @context[:ruby_desc_by_config_and_timestamp][config][ts] || "unknown"
                        # These fields are from the ResultSet summary
                        [ ts.strftime(time_format), this_point["mean"], this_point["stddev"], this_ruby_desc ]
                    else
                        nil
                    end
                end
                points.compact!
                next if points.empty?

                visible = @context[:selected_benchmarks].include?(benchmark)

                @series.push({ config: config, benchmark: benchmark, name: "#{config}-#{benchmark}", visible: visible, data: points })
            end
        end
        @series.sort_by! { |s| s[:name] }
    end

    def write_file(file_path)
        script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_timeline_d3_template.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(file_path + ".html", "w") { |f| f.write(html_output) }
    end
end

class MiniTimelinesReport < YJITMetrics::TimelineReport
    def self.report_name
        "mini_timelines"
    end

    def initialize(context)
        super

        config_x86 = "x86_64_prod_ruby_with_yjit"
        config_arm = "aarch64_prod_ruby_with_yjit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = []

        @context[:selected_benchmarks].each do |benchmark|
            [config_x86, config_arm].each do |config|
                platform = (config == config_x86) ? "x86_64" : "aarch64"
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

                @series.push({ config: config, benchmark: benchmark, name: "#{config}-#{benchmark}", platform: platform, data: points })
            end
        end
        #@series.sort_by! { |s| s[:name] }
    end

    def write_file(file_path)
        script_template = ERB.new File.read(__dir__ + "/../report_templates/mini_timeline_d3_template.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(file_path + ".html", "w") { |f| f.write(html_output) }
    end
end
