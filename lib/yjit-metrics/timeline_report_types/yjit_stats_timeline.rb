class YJITSpeedupTimelineReport < YJITMetrics::TimelineReport
    def self.report_name
        "yjit_stats_timeline"
    end

    # These objects have *gigantic* internal state. For debuggability, don't print the whole thing.
    def inspect
        "YJITSpeedupTimelineReport<#{object_id}>"
    end

    NUM_RECENT=100
    def initialize(context)
        super

        yjit_config_root = "prod_ruby_with_yjit"
        stats_config_root = "yjit_stats"
        no_jit_config_root = "prod_ruby_no_jit"
        x86_stats_config = "x86_64_#{stats_config_root}"

        # This should match the JS parser in the template file
        time_format = "%Y %m %d %H %M %S"

        @series = {}
        YJITMetrics::PLATFORMS.each { |platform| @series[platform] = { :recent => [], :all_time => [] } }

        @context[:benchmark_order].each do |benchmark|
            YJITMetrics::PLATFORMS.each do |platform|
                yjit_config = "#{platform}_#{yjit_config_root}"
                stats_config = "#{platform}_#{stats_config_root}"
                no_jit_config = "#{platform}_#{no_jit_config_root}"
                points = @context[:timestamps_with_stats].map do |ts|
                    this_point_yjit = @context[:summary_by_timestamp].dig(ts, yjit_config, benchmark)
                    this_point_cruby = @context[:summary_by_timestamp].dig(ts, no_jit_config, benchmark)
                    # If no same-platform stats, fall back to x86_64 stats if available
                    this_point_stats = @context[:summary_by_timestamp].dig(ts, stats_config, benchmark) ||
                        @context[:summary_by_timestamp].dig(ts, x86_stats_config, benchmark)
                    if this_point_yjit && this_point_stats
                        this_ruby_desc = @context[:ruby_desc_by_config_and_timestamp][yjit_config][ts] || "unknown"
                        # These fields are from the ResultSet summary
                        out = {
                            time: ts.strftime(time_format),
                            yjit_speedup: this_point_cruby["mean"] / this_point_yjit["mean"],
                            ratio_in_yjit: this_point_stats["yjit_stats"]["yjit_ratio_pct"],
                            side_exits: this_point_stats["yjit_stats"]["side_exits"],
                            invalidation_count: this_point_stats["yjit_stats"]["invalidation_count"] || 0,
                            ruby_desc: this_ruby_desc,
                        }
                        if out[:ratio_in_yjit].nil? || out[:side_exits].nil? || out[:invalidation_count].nil?
                            puts "Problem location: Benchmark #{benchmark.inspect} platform #{platform.inspect} timestamp #{ts.inspect}"
                            puts "Stats config(s): #{stats_config.inspect} / #{x86_stats_config.inspect}"
                            puts "Bad output sample: #{out.inspect}"
                            puts "Stats array: #{this_point_stats["yjit_stats"]}"
                            raise("Found point with nil as summary!")
                        end
                        out
                    else
                        nil
                    end
                end
                points.compact!
                next if points.empty?

                visible = @context[:selected_benchmarks].include?(benchmark)

                s = { config: yjit_config, benchmark: benchmark, name: "#{yjit_config_root}-#{benchmark}", platform: platform, visible: visible, data: points }
                s_recent = { config: yjit_config, benchmark: benchmark, name: "#{yjit_config_root}-#{benchmark}", platform: platform, visible: visible, data: points.last(NUM_RECENT) }
                @series[platform][:all_time].push s
                @series[platform][:recent].push s_recent
            end
        end

        # Grab the stats fields from the first stats point (for the first platform that has data).
        @stats_fields = @series.values.reject { |v| v[:all_time].empty? }[0][:all_time][0][:data][0].keys - [:time, :ruby_desc]

        # Calculate overall yjit speedup, yjit ratio, etc. over all benchmarks per-platform
        YJITMetrics::PLATFORMS.each do |platform|
            yjit_config = "#{platform}_#{yjit_config_root}"
            # No Ruby desc for this? If so, that means no results for this platform
            next unless @context[:ruby_desc_by_config_and_timestamp][yjit_config]

            data_mean = []
            data_geomean = []
            @context[:timestamps_with_stats].map.with_index do |ts, t_idx|
                # No Ruby desc for this platform/timestamp combo? If so, that means no results for this platform and timestamp.
                next unless @context[:ruby_desc_by_config_and_timestamp][yjit_config][ts]

                ruby_desc = @context[:ruby_desc_by_config_and_timestamp][yjit_config][ts] || "unknown"
                point_mean = {
                    time: ts.strftime(time_format),
                    ruby_desc: ruby_desc,
                }
                point_geomean = point_mean.dup
                @stats_fields.each do |field|
                    begin
                        points = @context[:benchmark_order].map.with_index do |bench, b_idx|
                            t_str = ts.strftime(time_format)
                            this_bench_data = @series[platform][:all_time][b_idx]
                            if this_bench_data
                                t_in_series = this_bench_data[:data].detect { |point_info| point_info[:time] == t_str }
                                t_in_series ? t_in_series[field] : nil
                            else
                                nil
                            end
                        end
                    rescue
                        STDERR.puts "Error in yjit_stats_timeline calculating field #{field} for TS #{ts.inspect} for all #{platform} benchmarks"
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
            overall_mean = { config: yjit_config, benchmark: "overall-mean", name: "#{yjit_config_root}-overall-mean", platform: platform, visible: true, data: data_mean }
            overall_geomean = { config: yjit_config, benchmark: "overall-geomean", name: "#{yjit_config_root}-overall-geomean", platform: platform, visible: true, data: data_geomean }
            overall_mean_recent = { config: yjit_config, benchmark: "overall-mean", name: "#{yjit_config_root}-overall-mean", platform: platform, visible: true, data: data_mean.last(NUM_RECENT) }
            overall_geomean_recent = { config: yjit_config, benchmark: "overall-geomean", name: "#{yjit_config_root}-overall-geomean", platform: platform, visible: true, data: data_geomean.last(NUM_RECENT) }

            @series[platform][:all_time].prepend overall_geomean
            @series[platform][:all_time].prepend overall_mean
            @series[platform][:recent].prepend overall_geomean_recent
            @series[platform][:recent].prepend overall_mean_recent
        end

        # Recent and all-time series have different numbers of benchmarks. To keep everybody in sync, we set
        # the colours here in Ruby and pass them through.
        color_by_benchmark = {}
        (["overall-mean", "overall-geomean"] + @context[:benchmark_order]).each.with_index do |bench, idx|
            color_by_benchmark[bench] = MUNIN_PALETTE[idx % MUNIN_PALETTE.size]
        end
        @series.each do |platform, hash|
            hash.each do |duration, all_series|
                all_series.each.with_index do |series, idx|
                    series[:color] = color_by_benchmark[series[:benchmark]]
                    if series[:color].nil?
                        raise "Error for #{platform} #{duration} w/ bench #{series[:benchmark].inspect}!"
                    end
                end
            end
        end
    end

    def write_files(out_dir)
        [:recent, :all_time].each do |duration|
            YJITMetrics::PLATFORMS.each do |platform|
                begin
                    @data_series = @series[platform][duration]

                    script_template = ERB.new File.read(__dir__ + "/../report_templates/yjit_stats_timeline_data_template.js.erb")
                    text = script_template.result(binding)
                    File.open("#{out_dir}/reports/timeline/yjit_stats_timeline.data.#{platform}.#{duration}.js", "w") { |f| f.write(text) }
                rescue
                    puts "Error writing data file for #{platform} #{duration} data!"
                    raise
                end
            end
        end

        script_template = ERB.new File.read(__dir__ + "/../report_templates/yjit_stats_timeline_d3_template.html.erb")
        #File.write("/tmp/erb_template.txt", script_template.src)
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open("#{out_dir}/_includes/reports/yjit_stats_timeline.html", "w") { |f| f.write(html_output) }
    end
end
