class BlogTimelineReport < YJITMetrics::TimelineReport
    def self.report_name
        "blog_timeline"
    end

    def self.report_extensions
        [ "html", "recent.html" ]
    end

    # These objects have *gigantic* internal state. For debuggability, don't print the whole thing.
    def inspect
        "BlogTimelineReport<#{object_id}>"
    end

    REPORT_PLATFORMS=["x86_64", "aarch64"]
    NUM_RECENT=100
    def initialize(context)
        super

        yjit_config_root = "prod_ruby_with_yjit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = {}
        REPORT_PLATFORMS.each { |platform| @series[platform] = { :recent => [], :all_time => [] } }

        @context[:benchmark_order].each.with_index do |benchmark, idx|
            color = MUNIN_PALETTE[idx % MUNIN_PALETTE.size]
            REPORT_PLATFORMS.each do |platform|
                config = "#{platform}_#{yjit_config_root}"
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

                s_all_time = { config: config, benchmark: benchmark, name: "#{yjit_config_root}-#{benchmark}", platform: platform, visible: visible, color: color, data: points }
                s_recent = s_all_time.dup
                s_recent[:data] = s_recent[:data].last(NUM_RECENT)

                @series[platform][:recent].push s_recent
                @series[platform][:all_time].push s_all_time
            end
        end
    end

    def write_files(out_dir)
        [:recent, :all_time].each do |duration|
            REPORT_PLATFORMS.each do |platform|
                begin
                    @data_series = @series[platform][duration]

                    script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_timeline_data_template.js.erb")
                    text = script_template.result(binding)
                    File.open("#{out_dir}/reports/timeline/blog_timeline.data.#{platform}.#{duration}.js", "w") { |f| f.write(text) }
                rescue
                    puts "Error writing data file for #{platform} #{duration} data!"
                    raise
                end
            end
        end

        script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_timeline_d3_template.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open("#{out_dir}/_includes/reports/blog_timeline.html", "w") { |f| f.write(html_output) }
    end
end

class MiniTimelinesReport < YJITMetrics::TimelineReport
    def self.report_name
        "mini_timelines"
    end

    # These objects have *gigantic* internal state. For debuggability, don't print the whole thing.
    def inspect
        "MiniTimelinesReport<#{object_id}>"
    end

    def initialize(context)
        super

        config_x86 = "x86_64_prod_ruby_with_yjit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = []

        @context[:selected_benchmarks].each do |benchmark|
            platform = "x86_64"
            config = config_x86

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
        #@series.sort_by! { |s| s[:name] }
    end

    def write_files(out_dir)
        script_template = ERB.new File.read(__dir__ + "/../report_templates/mini_timeline_d3_template.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open("#{out_dir}/_includes/reports/mini_timelines.html", "w") { |f| f.write(html_output) }
    end
end
