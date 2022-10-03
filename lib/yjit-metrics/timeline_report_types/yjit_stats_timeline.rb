class YJITSpeedupTimelineReport < YJITMetrics::TimelineReport
    def self.report_name
        "yjit_stats_timeline"
    end

    REPORT_PLATFORMS = ["x86_64", "aarch64"]
    def initialize(context)
        super

        yjit_config_root = "prod_ruby_with_yjit"
        stats_config_root = "yjit_stats"
        no_jit_config_root = "prod_ruby_no_jit"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = []

        @context[:benchmark_order].each do |benchmark|
            REPORT_PLATFORMS.each do |platform|
                yjit_config = "#{platform}_#{yjit_config_root}"
                stats_config = "#{platform}_#{stats_config_root}"
                no_jit_config = "#{platform}_#{no_jit_config_root}"
                points = @context[:timestamps_with_stats].map do |ts|
                    this_point_yjit = @context[:summary_by_timestamp].dig(ts, yjit_config, benchmark)
                    this_point_cruby = @context[:summary_by_timestamp].dig(ts, no_jit_config, benchmark)
                    this_point_stats = @context[:summary_by_timestamp].dig(ts, stats_config, benchmark)
                    if this_point_yjit && this_point_stats
                        this_ruby_desc = @context[:ruby_desc_by_config_and_timestamp][yjit_config][ts] || "unknown"
                        # These fields are from the ResultSet summary
                        {
                            time: ts.strftime(time_format),
                            yjit_speedup: this_point_cruby["mean"] / this_point_yjit["mean"],
                            ratio_in_yjit: this_point_stats["yjit_stats"]["yjit_ratio_pct"],
                            side_exits: this_point_stats["yjit_stats"]["side_exits"],
                            invalidation_count: this_point_stats["yjit_stats"]["invalidation_count"] || 0,
                            ruby_desc: this_ruby_desc,
                        }
                    else
                        nil
                    end
                end
                points.compact!
                next if points.empty?

                visible = @context[:selected_benchmarks].include?(benchmark)

                @series.push({ config: yjit_config, benchmark: benchmark, name: "#{yjit_config}-#{benchmark}", visible: visible, data: points })
            end
        end

        stats_fields = @series[0][:data][0].keys - [:time, :ruby_desc]

        # Calculate overall yjit speedup, yjit ratio, etc. over all benchmarks per-platform
        REPORT_PLATFORMS.each do |platform|
            yjit_config = "#{platform}_#{yjit_config_root}"
            # No Ruby desc for this? If so, that means no results for this platform
            next unless @context[:ruby_desc_by_config_and_timestamp][yjit_config]

            data_mean = []
            data_geomean = []
            @context[:timestamps_with_stats].map.with_index do |ts, t_idx|
                # No Ruby desc for this platform/timestamp combo? If so, that means no results for this platform.
                next unless @context[:ruby_desc_by_config_and_timestamp][yjit_config][ts]

                ruby_desc = @context[:ruby_desc_by_config_and_timestamp][yjit_config][ts] || "unknown"
                point_mean = {
                    time: ts.strftime(time_format),
                    ruby_desc: ruby_desc,
                }
                point_geomean = point_mean.dup
                stats_fields.each do |field|
                    begin
                        points = @context[:benchmark_order].map.with_index do |bench, b_idx|
                            t_str = ts.strftime(time_format)
                            t_in_series = @series[b_idx][:data].detect { |point_info| point_info[:time] == t_str }
                            t_in_series ? t_in_series[field] : nil
                        end
                    rescue
                        STDERR.puts "Error in yjit_stats_timeline calculating field #{field} for TS #{ts.inspect} for all benchmarks"
                        raise
                    end
                    points.compact!
                    raise("No data points for stat #{field.inspect} for TS #{ts.inspect}") if points.empty?
                    point_mean[field] = mean(points)
                    point_geomean[field] = geomean(points)
                end

                data_mean.push(point_mean)
                data_geomean.push(point_geomean)
            end
            overall_mean = { config: yjit_config, benchmark: "overall-mean", name: "#{yjit_config}-overall-mean", visible: true, data: data_mean }
            overall_geomean = { config: yjit_config, benchmark: "overall-geomean", name: "#{yjit_config}-overall-geomean", visible: true, data: data_geomean }

            @series.prepend overall_geomean
            @series.prepend overall_mean
        end
    end

    def write_file(file_path)
        script_template = ERB.new File.read(__dir__ + "/../report_templates/yjit_stats_timeline_d3_template.html.erb")
        #File.write("/tmp/erb_template.txt", script_template.src)
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(file_path + ".html", "w") { |f| f.write(html_output) }
    end
end
