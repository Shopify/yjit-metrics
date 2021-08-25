require_relative "yjit_stats_reports"

class YJITMetrics::CompareReport < YJITMetrics::YJITStatsReport
    def exactly_one_config_with_name(configs, substring, description)
        matching_configs = configs.select { |name| name.include?(substring) }
        raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
        raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty?
        matching_configs[0]
    end

    # Include Truffle data only if we can find it
    def look_up_data_by_ruby(in_runs: false)
        @with_yjit_config = exactly_one_config_with_name(@config_names, "with_yjit", "with-YJIT")
        @with_mjit_config = exactly_one_config_with_name(@config_names, "with_mjit", "with-MJIT")
        @no_jit_config    = exactly_one_config_with_name(@config_names, "no_jit", "no-JIT")
        @truffle_config   = exactly_one_config_with_name(@config_names, "truffleruby", "Truffle")

        @configs_with_human_names = [
            ["No JIT", @no_jit_config],
            ["YJIT", @with_yjit_config],
            ["MJIT", @with_mjit_config],
        ]
        @configs_with_human_names.push(["Truffle", @truffle_config]) if @truffle_config

        # Grab relevant data from the ResultSet
        @times_by_config = {}
        [ @with_yjit_config, @with_mjit_config, @no_jit_config, @truffle_config ].compact.each do|config|
            @times_by_config[config] = @result_set.times_for_config_by_benchmark(config, in_runs: in_runs)
        end
        @yjit_stats = @result_set.yjit_stats_for_config_by_benchmark(@stats_config, in_runs: in_runs)

        @benchmark_names = filter_benchmark_names(@times_by_config[@with_yjit_config].keys)

        @times_by_config.each do |config_name, config_results|
            if config_results.nil? || config_results.empty?
                raise("No results for configuration #{config_name.inspect} in #{self.class}!")
            end
            no_result_benchmarks = @benchmark_names.select { |bench_name| config_results[bench_name].nil? || config_results[bench_name].empty? }
            unless no_result_benchmarks.empty?
                raise("No results in config #{config_name.inspect} for benchmark(s) #{no_result_benchmarks.inspect} in #{self.class}!")
            end
        end
    end

end

# This report is to compare YJIT's time-in-JIT versus its speedup for various benchmarks.
class YJITMetrics::CompareSpeedReport < YJITMetrics::CompareReport
    def self.report_name
        "compare_speed"
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the YJIT stats parent class
        super

        look_up_data_by_ruby

        no_stats_benchmarks = @benchmark_names.select { |bench_name| !@yjit_stats[bench_name] || !@yjit_stats[bench_name][0] || @yjit_stats[bench_name][0].empty? }
        unless no_stats_benchmarks.empty?
            raise "No YJIT stats found for benchmarks: #{no_stats_benchmarks.inspect}"
        end

        # Sort benchmarks by compiled ISEQ count
        @benchmark_names.sort_by! { |bench_name| @yjit_stats[bench_name][0]["compiled_iseq_count"] }

        @headings = [ "bench" ] +
            @configs_with_human_names.flat_map { |name, config| [ "#{name} (ms)", "#{name} RSD" ] } +
            @configs_with_human_names.flat_map { |name, config| config == @no_jit_config ? [] : [ "#{name} spd", "#{name} spd RSD" ] } +
            [ "% in YJIT" ]
        # Col formats are only used when formatting a text table, not for HTML or CSV
        @col_formats = [ "%s" ] +                                           # Benchmark name
            [ "%.1f", "%.2f%%" ] * @configs_with_human_names.size +         # Mean and RSD per-Ruby
            [ "%.2fx", "%.2f%%" ] * (@configs_with_human_names.size - 1) +  # Speedups per-Ruby
            [ "%.2f%%" ]                                                    # YJIT ratio

        @mean_by_config = {
            @no_jit_config => [],
            @with_mjit_config => [],
            @with_yjit_config => [],
            @truffle_config => [],
        }
        @rsd_by_config = {
            @no_jit_config => [],
            @with_mjit_config => [],
            @with_yjit_config => [],
            @truffle_config => [],
        }
        @speedup_by_config = {
            @with_mjit_config => [],
            @with_yjit_config => [],
            @truffle_config => [],
        }
        @yjit_ratio = []

        @benchmark_names.each do |benchmark_name|
            @configs_with_human_names.each do |name, config|
                this_config_times = @times_by_config[config][benchmark_name]
                this_config_mean = mean(this_config_times)
                @mean_by_config[config].push this_config_mean
                this_config_rel_stddev_pct = rel_stddev_pct(this_config_times)
                @rsd_by_config[config].push this_config_rel_stddev_pct
            end

            no_jit_mean = @mean_by_config[@no_jit_config][-1] # Last pushed -- the one for this benchmark
            no_jit_rel_stddev = @rsd_by_config[@no_jit_config][-1]
            @configs_with_human_names.each do |name, config|
                next if config == @no_jit_config

                this_config_mean = @mean_by_config[config][-1]
                this_config_rel_stddev = @rsd_by_config[config][-1]
                speed_ratio = this_config_mean / no_jit_mean
                speed_rel_stddev = Math.sqrt(no_jit_rel_stddev * no_jit_rel_stddev + this_config_rel_stddev * this_config_rel_stddev)
                @speedup_by_config[config].push [ speed_ratio, speed_rel_stddev ]
            end

            # A benchmark run may well return multiple sets of YJIT stats per benchmark name/type.
            # For these calculations we just add all relevant counters together.
            this_bench_stats = combined_stats_data_for_benchmarks([benchmark_name])

            total_exits = total_exit_count(this_bench_stats)
            retired_in_yjit = this_bench_stats["exec_instruction"] - total_exits
            total_insns_count = retired_in_yjit + this_bench_stats["vm_insns_count"]
            yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count
            @yjit_ratio.push yjit_ratio_pct
        end
    end

    def report_table_data
        @benchmark_names.map.with_index do |bench_name, idx|
            [ bench_name ] +
                @configs_with_human_names.flat_map { |name, config| [ @mean_by_config[config][idx], @rsd_by_config[config][idx] ] } +
                @configs_with_human_names.flat_map { |name, config| config == @no_jit_config ? [] : @speedup_by_config[config][idx] } +
                [ @yjit_ratio[idx] ]
        end
    end

    def to_s
        format_as_table(@headings, @col_formats, report_table_data) +
            "\nRSD is relative standard deviation (stddev / mean), expressed as a percent.\n" +
            "Spd is the speed (iters/second) of the optimised implementation -- 2.0x would be twice as many iters per second.\n"
    end

    def to_pct(ratio)
        (ratio * 100.0).to_s + "%"
    end

    # These will be assigned in order to each Ruby
    RUBY_BAR_COLOURS = [ "blue", "orange", "green", "red" ]

    def svg_object
        # If we render a comparative report to file, we need victor for SVG output.
        require "victor"

        svg = Victor::SVG.new template: :minimal, style: { }  # background: '#ddd'

        axis_colour = "#000"
        background_colour = "#EEE"
        text_colour = "#111"

        # Reserve the left 15% of the width for the axis scale numbers. Right 5% is whitespace.
        left_axis_width = 0.15
        right_whitespace = 0.05

        # Reserve the top 5% as whitespace, and the bottom 20% for benchmark names.
        bottom_key_height = 0.20
        top_whitespace = 0.05

        plot_left_edge = left_axis_width
        plot_top_edge = top_whitespace
        plot_width = 1.0 - left_axis_width - right_whitespace
        plot_height = 1.0 - bottom_key_height - top_whitespace

        svg.rect x: to_pct(plot_left_edge), y: to_pct(plot_top_edge),
            width: to_pct(plot_width), height: to_pct(plot_height),
            stroke: axis_colour, fill: background_colour


        # Basic info on Ruby configs and benchmarks
        ruby_configs = @configs_with_human_names.map { |name, config| config }
        ruby_config_bar_colour = Hash[ruby_configs.zip(RUBY_BAR_COLOURS)]
        n_configs = ruby_configs.size
        n_benchmarks = @benchmark_names.size


        # How high to speedup ratios go?
        max_speedup_ratio = @speedup_by_config.values.map { |speedup_by_bench| speedup_by_bench.map(&:first).max }.max


        # Now let's calculate some widths...

        # Within each benchmark's horizontal span we'll want 3 or 4 bars plus a bit of whitespace.
        # And we'll reserve 5% of the plot's width for whitespace on the far left and again on the far right.
        plot_padding_ratio = 0.05
        plot_effective_width = plot_width * (1.0 - 2 * plot_padding_ratio)
        plot_effective_left = plot_left_edge + plot_width * plot_padding_ratio
        each_bench_width = plot_effective_width / n_benchmarks
        bar_width = each_bench_width / (n_configs + 1)

        first_bench_left_edge = plot_left_edge + (plot_width * plot_padding_ratio)
        bench_left_edge = (0...n_benchmarks).map { |idx| first_bench_left_edge + idx * each_bench_width }


        # And some heights...
        plot_top_whitespace = 0.05 * plot_height
        plot_effective_top = plot_top_edge + plot_top_whitespace
        plot_effective_height = plot_height - plot_top_whitespace


        # Set up the top legend with coloured boxes and Ruby config names
        top_legend_box_height = 0.04
        top_legend_box_width = 0.08
        top_legend_text_height = 0.03
        legend_box_stroke_colour = "#888"
        top_legend_item_width = plot_effective_width / n_configs
        n_configs.times do |config_idx|
            item_center_x = plot_effective_left + top_legend_item_width * (config_idx + 0.5)
            item_center_y = plot_effective_top + 0.025
            svg.rect \
                x: to_pct(item_center_x - 0.5 * top_legend_box_width),
                y: to_pct(item_center_y - 0.5 * top_legend_box_height),
                width: to_pct(top_legend_box_width),
                height: to_pct(top_legend_box_height),
                fill: ruby_config_bar_colour[ruby_configs[config_idx]],
                stroke: legend_box_stroke_colour
            svg.text @configs_with_human_names[config_idx][0],
                x: to_pct(item_center_x), y: to_pct(item_center_y + 0.5 * top_legend_text_height),
                height: top_legend_text_height,
                text_anchor: "middle",
                font_weight: "bold",
                fill: text_colour
        end


        # Okay. Now let's plot a lot of boxes and whiskers.
        @benchmark_names.each.with_index do |bench_name, bench_idx|
            no_jit_mean = @mean_by_config[@no_jit_config][bench_idx]

            bars_width_start = bench_left_edge[bench_idx]
            ruby_configs.each.with_index do |config, config_idx|
                if config == @no_jit_config
                    speedup = 1.0 # No-JIT is always exactly 1x No-JIT
                    rsd = @rsd_by_config[@no_jit_config][bench_idx]
                else
                    speedup, rsd = @speedup_by_config[config][bench_idx]
                end
                bar_height_ratio = speedup / max_speedup_ratio;

                svg.rect \
                    x: to_pct(bars_width_start + config_idx * bar_width),
                    y: to_pct(plot_effective_top + (1.0 - bar_height_ratio) * plot_effective_height),
                    width: to_pct(bar_width),
                    height: to_pct(bar_height_ratio * plot_effective_height),
                    fill: ruby_config_bar_colour[config]
            end
        end

        svg
    end

    def write_file(filename)
        require "victor"

        @svg = svg_object

        script_template = ERB.new File.read(__dir__ + "/../report_templates/compare_speed.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(filename + ".html", "w") { |f| f.write(html_output) }

        #write_to_csv(filename + ".csv", [@headings] + report_table_data)
    end

end
