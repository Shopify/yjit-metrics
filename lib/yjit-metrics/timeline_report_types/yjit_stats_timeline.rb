class YJITSpeedupTimelineReport < YJITMetrics::TimelineReport
    def self.report_name
        "yjit_stats_timeline"
    end

    def initialize(context)
        super

        yjit_config = "prod_ruby_with_yjit"
        stats_config = "yjit_stats"
        no_jit_config = "prod_ruby_no_jit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = []

        @context[:benchmark_order].each do |benchmark|
            all_points = @context[:timestamps].map do |ts|
                this_point = @context[:summary_by_timestamp].dig(ts, yjit_config, benchmark)
                this_point_cruby = @context[:summary_by_timestamp].dig(ts, no_jit_config, benchmark)
                this_point_stats = @context[:summary_by_timestamp].dig(ts, stats_config, benchmark)
                this_ruby_desc = @context[:ruby_desc_by_timestamp][ts] || "unknown"
                if this_point
                    # These fields are from the ResultSet summary
                    {
                        time: ts.strftime(time_format),
                        yjit_speedup: this_point_cruby["mean"] / this_point["mean"],
                        ratio_in_yjit: this_point_stats["yjit_stats"]["yjit_ratio_pct"],
                        side_exits: this_point_stats["yjit_stats"]["side_exits"],
                        invalidation_count: this_point_stats["yjit_stats"]["invalidation_count"] || 0,
                        ruby_desc: this_ruby_desc,
                    }
                else
                    nil
                end
            end

            visible = @context[:selected_benchmarks].include?(benchmark)

            @series.push({ config: yjit_config, benchmark: benchmark, name: "#{yjit_config}-#{benchmark}", visible: visible, data: all_points.compact })
        end

        stats_fields = @series[0][:data][0].keys - [:time, :ruby_desc]
        # Calculate overall yjit speedup, yjit ratio, etc. over all benchmarks
        summary = @context[:timestamps].map.with_index do |ts, t_idx|
            out = {
                time: ts.strftime(time_format),
                ruby_desc: @context[:ruby_desc_by_timestamp][ts] || "unknown",
            }
            stats_fields.each do |field|
                begin
                    points = @context[:benchmark_order].map.with_index do |bench, b_idx|
                        t_in_series = @series[b_idx][:data][t_idx]
                        t_in_series ? t_in_series[field] : nil
                    end
                rescue
                    STDERR.puts "Error in yjit_stats_timeline calculating field #{field} for TS #{ts.inspect} for all benchmarks"
                    raise
                end
                points.compact!
                raise("No data points for stat #{field.inspect} for TS #{ts.inspect}") if points.empty?
                out[field] = mean(points)
            end

            out
        end
        overall = { config: yjit_config, benchmark: "overall", name: "#{yjit_config}-overall", visible: true, data: summary.compact }

        @series.sort_by! { |s| s[:name] }
        @series.prepend overall
    end

    def write_file(file_path)
        script_template = ERB.new File.read(__dir__ + "/../report_templates/yjit_stats_timeline_d3_template.html.erb")
        #File.write("/tmp/erb_template.txt", script_template.src)
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(file_path + ".html", "w") { |f| f.write(html_output) }
    end
end
