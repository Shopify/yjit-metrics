require_relative "yjit_stats_reports"

# For details-at-a-specific-time reports, we'll want to find individual configs and make sure everything is
# present and accounted for. This is a "single" report in the sense that it's conceptually at a single
# time, even though it can be multiple runs and Rubies. What it is *not* is results over time as YJIT and
# the benchmarks change.
class YJITMetrics::BloggableSingleReport < YJITMetrics::YJITStatsReport

    REALNESS_THRESHOLD = 2 # How real is "basically real"?

    # The bloggable reports separate benchmarks by their degree of real-world-ness/realness.
    BENCHMARK_METADATA = {
        # Highly synthetic microbenchmarks
        "30k_ifelse" => {
            realness: 0,
            single_file: true,
            desc: "30_ifelse tests thousands of nested methods containing simple if/else statements.",
        },
        "30k_methods" => {
            realness: 0,
            single_file: true,
            desc: "30_methods tests thousands of nested method calls that mostly just call out to other single-call methods.",
        },
        "cfunc_itself" => {
            realness: 0,
            single_file: true,
            desc: "cfunc_itself just calls the 'itself' method many, many times.",
        },
        "fib" => {
            realness: 0,
            single_file: true,
            desc: "Fib is a simple exponential-time recursive Fibonacci number generator.",
        },
        "getivar" => {
            realness: 0,
            single_file: true,
            desc: "getivar tests the performance of getting instance variable values.",
        },
        "setivar" => {
            realness: 0,
            single_file: true,
            desc: "setivar tests the performance of setting instance variable values.",
        },
        "respond_to" => {
            realness: 0,
            single_file: true,
            desc: "respond_to tests the performance of the respond_to? method.",
        },

        # "Shootout" benchmarks, from places like The Computer Language Benchmarks Game
        "binarytrees" => {
            realness: 1,
            desc: "binarytrees from the Computer Language Benchmarks Game.",
        },
        "fannkuchredux" => {
            realness: 1,
            desc: "fannkuchredux from the Computer Language Benchmarks Game.",
        },
        "nbody" => {
            realness: 1,
            desc: "nbody from the Computer Language Benchmarks Game.",
        },

        # Synthetic benchmarks with some measure of real-world functionality (e.g. simple library load-tests)
        "activerecord" => {
            realness: 2,
            desc: "activeRecord repeatedly queries entries in a SQLite table with highly-random names.",
        },
        "psych-load" => {
            realness: 2,
            desc: "psych-load repeatedly loads a small selection of YAML files taken from various OSS projects.",
        },
        "mail" => {
            realness: 2,
            desc: "mail tests the Mail gem by repeatedly creating an email from a text file and converting it to a string for sending.",
        },
        "liquid-render" => {
            realness: 2,
            desc: "liquid-render renders a chosen-for-profiling Liquid theme repeatedly.",
        },
        "jekyll" => {
            realness: 2,
            unstable: 1, # jekyll has known problems including some kind of resource leak. Jekyll's real, but this usage method is flawed.
            desc: "jekyll reviews and rebuilds a Jekyll site, but is almost entirely scanning directories of files that didn't change.",
        },

        # Real-esque benchmarks that you could pretend are real for a blog post or a paper
        "lee" => {
            realness: 3,
            desc: "lee is a Lee's Method Sudoku solver, deployed in a plausibly reality-like way",
        },
        "railsbench" => {
            realness: 3,
            desc: "railsbench is a read-only tiny SQLite-backed Rails app, querying a small selection of .html.erb routes and JSON routes.",
        },
        "optcarrot" => {
            realness: 3,
            desc: "optcarrot is a functional headless NES emulator, run on a specific game cartridge for a specific number of frames.",
        },

    }

    def realish_benchmarks
        @benchmark_names.select { |bench| BENCHMARK_METADATA[bench][:realness] >= REALNESS_THRESHOLD }
    end

    def exactly_one_config_with_name(configs, substring, description, none_okay: false)
        matching_configs = configs.select { |name| name.include?(substring) }
        raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
        raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty? && !none_okay
        matching_configs[0]
    end

    # Include Truffle data only if we can find it
    def look_up_data_by_ruby(in_runs: false)
        @with_yjit_config = exactly_one_config_with_name(@config_names, "with_yjit", "with-YJIT")
        @with_mjit_config = exactly_one_config_with_name(@config_names, "with_mjit", "with-MJIT")
        @no_jit_config    = exactly_one_config_with_name(@config_names, "no_jit", "no-JIT")
        @truffle_config   = exactly_one_config_with_name(@config_names, "truffleruby", "Truffle", none_okay: true)

        @configs_with_human_names = [
            ["No JIT", @no_jit_config],
            ["MJIT", @with_mjit_config],
            ["YJIT", @with_yjit_config],
        ]
        @configs_with_human_names.push(["Truffle", @truffle_config]) if @truffle_config

        # Grab relevant data from the ResultSet
        @times_by_config = {}
        @ruby_metadata_by_config = {}
        @bench_metadata_by_config = {}
        [ @with_yjit_config, @with_mjit_config, @no_jit_config, @truffle_config ].compact.each do|config|
            @times_by_config[config] = @result_set.times_for_config_by_benchmark(config, in_runs: in_runs)
            @ruby_metadata_by_config[config] = @result_set.metadata_for_config(config)
            @bench_metadata_by_config[config] = @result_set.benchmark_metadata_for_config_by_benchmark(config)
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

        no_stats_benchmarks = @benchmark_names.select { |bench_name| !@yjit_stats[bench_name] || !@yjit_stats[bench_name][0] || @yjit_stats[bench_name][0].empty? }
        unless no_stats_benchmarks.empty?
            raise "No YJIT stats found for benchmarks: #{no_stats_benchmarks.inspect}"
        end
    end

    def calc_stats_by_config
        @mean_by_config = {
            @no_jit_config => [],
            @with_mjit_config => [],
            @with_yjit_config => [],
        }
        @rsd_pct_by_config = {
            @no_jit_config => [],
            @with_mjit_config => [],
            @with_yjit_config => [],
        }
        @speedup_by_config = {
            @with_mjit_config => [],
            @with_yjit_config => [],
        }
        @total_time_by_config = {
            @no_jit_config => 0.0,
            @with_mjit_config => 0.0,
            @with_yjit_config => 0.0,
        }
        if @truffle_config
            @mean_by_config[@truffle_config] = []
            @rsd_pct_by_config[@truffle_config] = []
            @speedup_by_config[@truffle_config] = []
            @total_time_by_config[@truffle_config] = 0.0
        end
        @yjit_ratio = []

        @benchmark_names.each do |benchmark_name|
            @configs_with_human_names.each do |name, config|
                this_config_times = @times_by_config[config][benchmark_name]
                this_config_mean = mean(this_config_times)
                @mean_by_config[config].push this_config_mean
                @total_time_by_config[config] += this_config_times.sum
                this_config_rel_stddev_pct = rel_stddev_pct(this_config_times)
                @rsd_pct_by_config[config].push this_config_rel_stddev_pct
            end

            no_jit_mean = @mean_by_config[@no_jit_config][-1] # Last pushed -- the one for this benchmark
            no_jit_rel_stddev_pct = @rsd_pct_by_config[@no_jit_config][-1]
            no_jit_rel_stddev = no_jit_rel_stddev_pct / 100.0  # Get ratio, not percent
            @configs_with_human_names.each do |name, config|
                next if config == @no_jit_config

                this_config_mean = @mean_by_config[config][-1]
                this_config_rel_stddev_pct = @rsd_pct_by_config[config][-1]
                this_config_rel_stddev = this_config_rel_stddev_pct / 100.0 # Get ratio, not percent
                speed_ratio = no_jit_mean / this_config_mean
                speed_rel_stddev = Math.sqrt(no_jit_rel_stddev * no_jit_rel_stddev + this_config_rel_stddev * this_config_rel_stddev)
                @speedup_by_config[config].push [ speed_ratio, speed_rel_stddev * 100.0 ]
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
end

# This report is to compare YJIT's speedup versus other Rubies for a single run or block of runs,
# with a single YJIT head-of-master.
class YJITMetrics::SpeedDetailsReport < YJITMetrics::BloggableSingleReport
    def self.report_name
        "blog_speed_details"
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the parent class, look up relevant data
        super

        # This can be set up using set_extra_info later.
        @filename_permalinks = {}

        look_up_data_by_ruby

        # Sort benchmarks by most-to-least real, and then alphabetically
        @benchmark_names.sort_by! { |bench_name| [ -BENCHMARK_METADATA[bench_name][:realness], bench_name ] }

        @headings = [ "bench" ] +
            @configs_with_human_names.flat_map { |name, config| [ "#{name} (ms)", "#{name} RSD" ] } +
            @configs_with_human_names.flat_map { |name, config| config == @no_jit_config ? [] : [ "#{name} spd", "#{name} spd RSD" ] } +
            [ "% in YJIT" ]
        # Col formats are only used when formatting entries for a text table, not for CSV
        @col_formats = [ "%s" ] +                                           # Benchmark name
            [ "%.1f", "%.2f%%" ] * @configs_with_human_names.size +         # Mean and RSD per-Ruby
            [ "%.2fx", "%.2f%%" ] * (@configs_with_human_names.size - 1) +  # Speedups per-Ruby
            [ "%.2f%%" ]                                                    # YJIT ratio

        calc_stats_by_config
    end

    def set_extra_info(info)
        super

        if info[:filenames]
            info[:filenames].each do |filename|
                @filename_permalinks[filename] = "https://shopify.github.io/yjit-metrics/raw_benchmark_data/#{filename}"
            end
        end
    end

    # Printed to console
    def report_table_data
        @benchmark_names.map.with_index do |bench_name, idx|
            [ bench_name ] +
                @configs_with_human_names.flat_map { |name, config| [ @mean_by_config[config][idx], @rsd_pct_by_config[config][idx] ] } +
                @configs_with_human_names.flat_map { |name, config| config == @no_jit_config ? [] : @speedup_by_config[config][idx] } +
                [ @yjit_ratio[idx] ]
        end
    end

    # Listed on the details page
    def details_report_table_data
        @benchmark_names.map.with_index do |bench_name, idx|
            bench_desc = BENCHMARK_METADATA[bench_name][:desc] || "(no description available)"
            if BENCHMARK_METADATA[:single_file]
                bench_url = "https://github.com/Shopify/yjit-bench/blob/main/benchmarks/#{bench_name}.rb"
            else
                bench_url = "https://github.com/Shopify/yjit-bench/blob/main/benchmarks/#{bench_name}/benchmark.rb"
            end
            [ "<a href=\"#{bench_url}\" title=\"#{bench_desc}\">#{bench_name}</a>" ] +
                @configs_with_human_names.flat_map { |name, config| [ @mean_by_config[config][idx], @rsd_pct_by_config[config][idx] ] } +
                @configs_with_human_names.flat_map { |name, config| config == @no_jit_config ? [] : @speedup_by_config[config][idx] } +
                [ @yjit_ratio[idx] ]
        end
    end

    def to_s
        # This is just used to print the table to the console
        format_as_table(@headings, @col_formats, report_table_data) +
            "\nRSD is relative standard deviation (stddev / mean), expressed as a percent.\n" +
            "Spd is the speed (iters/second) of the optimised implementation -- 2.0x would be twice as many iters per second.\n"
    end

    # For the SVG, we calculate ratios from 0 to 1 for how far across the graph area a coordinate is.
    # Then we convert them here to the actual size of the graph.
    def ratio_to_x(ratio)
        (ratio * 1000).to_s
    end

    def ratio_to_y(ratio)
        (ratio * 600.0).to_s
    end

    # These will be assigned in order to each Ruby
    RUBY_BAR_COLOURS = [ "#7070f8", "orange", "green", "red" ]

    def svg_object(benchmarks: @benchmark_names)
        # If we render a comparative report to file, we need victor for SVG output.
        require "victor"

        svg = Victor::SVG.new :template => :minimal,
            :viewBox => "0 0 1000 600",
            :xmlns => "http://www.w3.org/2000/svg",
            "xmlns:xlink" => "http://www.w3.org/1999/xlink"  # background: '#ddd'

        axis_colour = "#000"
        background_colour = "#EEE"
        text_colour = "#111"

        # Reserve some width on the left for the axis. Include a bit of right-side whitespace.
        left_axis_width = 0.05
        right_whitespace = 0.01

        # Reserve some height for the legend and bottom height for x-axis labels
        bottom_key_height = 0.17
        top_whitespace = 0.05

        plot_left_edge = left_axis_width
        plot_top_edge = top_whitespace
        plot_bottom_edge = 1.0 - bottom_key_height
        plot_width = 1.0 - left_axis_width - right_whitespace
        plot_height = 1.0 - bottom_key_height - top_whitespace

        svg.rect x: ratio_to_x(plot_left_edge), y: ratio_to_y(plot_top_edge),
            width: ratio_to_x(plot_width), height: ratio_to_y(plot_height),
            stroke: axis_colour, fill: background_colour


        # Basic info on Ruby configs and benchmarks
        ruby_configs = @configs_with_human_names.map { |name, config| config }
        ruby_human_names = @configs_with_human_names.map(&:first)
        ruby_config_bar_colour = Hash[ruby_configs.zip(RUBY_BAR_COLOURS)]
        n_configs = ruby_configs.size
        n_benchmarks = benchmarks.size


        # How high to speedup ratios go?
        max_speedup_ratio = benchmarks.map { |bench_name|
            bench_idx = @benchmark_names.index(bench_name)
            @speedup_by_config.values.map { |speedup_by_bench| speedup_by_bench[bench_idx][0] }.max
        }.max
        if max_speedup_ratio.nil?
            $stderr.puts "Error finding Y axis. Benchmarks: #{benchmarks.inspect}."
            $stderr.puts "Speedup data: #{@speedup_by_config.inspect}"
            raise "Error finding axis Y scale for benchmarks: #{benchmarks.inspect}"
        end
        #max_speedup_ratio = @speedup_by_config.values.map { |speedup_by_bench| speedup_by_bench.map(&:first).max }.max


        # Now let's calculate some widths...

        # Within each benchmark's horizontal span we'll want 3 or 4 bars plus a bit of whitespace.
        # And we'll reserve 5% of the plot's width for whitespace on the far left and again on the far right.
        plot_padding_ratio = 0.02
        plot_effective_width = plot_width * (1.0 - 2 * plot_padding_ratio)
        plot_effective_left = plot_left_edge + plot_width * plot_padding_ratio
        each_bench_width = plot_effective_width / n_benchmarks
        bar_width = each_bench_width / (n_configs + 1)

        first_bench_left_edge = plot_left_edge + (plot_width * plot_padding_ratio)
        bench_left_edge = (0...n_benchmarks).map { |idx| first_bench_left_edge + idx * each_bench_width }


        # And some heights...
        plot_top_whitespace = 0.07 * plot_height
        plot_effective_top = plot_top_edge + plot_top_whitespace
        plot_effective_height = plot_height - plot_top_whitespace


        # Add axis markers down the left side
        tick_length = 0.008
        font_size = "small"
        # This is the largest power-of-10 multiple of the no-JIT mean that we'd see on the axis. Often it's 1 (ten to the zero.)
        largest_power_of_10 = 10.0 ** Math.log10(max_speedup_ratio).to_i
        # Let's get some nice even numbers for possible distances between ticks
        candidate_division_values =
            [ largest_power_of_10 * 5, largest_power_of_10 * 2, largest_power_of_10, largest_power_of_10 / 2, largest_power_of_10 / 5,
                largest_power_of_10 / 10, largest_power_of_10 / 20 ]
        # We'll try to show between about 4 and 10 ticks along the axis, at nice even-numbered spots.
        division_value = candidate_division_values.detect do |div_value|
            divs_shown = (max_speedup_ratio / div_value).to_i
            divs_shown >= 4 && divs_shown <= 10
        end
        raise "Error figuring out axis scale with max speedup ratio: #{max_speedup_ratio.inspect} (pow10: #{largest_power_of_10.inspect})!" if division_value.nil?
        division_ratio_per_value = plot_effective_height / max_speedup_ratio

        # Now find all the x-axis tick locations
        divisions = []
        cur_div = 0.0
        loop do
            divisions.push cur_div
            cur_div += division_value
            break if cur_div > max_speedup_ratio
        end

        divisions.each do |div_value|
            tick_distance_from_zero = div_value / max_speedup_ratio
            tick_y = plot_effective_top + (1.0 - tick_distance_from_zero) * plot_effective_height
            svg.line x1: ratio_to_x(plot_left_edge - tick_length), y1: ratio_to_y(tick_y),
                x2: ratio_to_x(plot_left_edge), y2: ratio_to_y(tick_y),
                stroke: axis_colour
            svg.text ("%.1f" % div_value),
                x: ratio_to_x(plot_left_edge - 3 * tick_length), y: ratio_to_y(tick_y),
                text_anchor: "end",
                font_weight: "bold",
                font_size: font_size,
                fill: text_colour
        end

        # Set up the top legend with coloured boxes and Ruby config names
        top_legend_box_height = 0.03
        top_legend_box_width = 0.08
        top_legend_text_height = 0.025  # Turns out we can't directly specify this...
        legend_box_stroke_colour = "#888"
        top_legend_item_width = plot_effective_width / n_configs
        n_configs.times do |config_idx|
            item_center_x = plot_effective_left + top_legend_item_width * (config_idx + 0.5)
            item_center_y = plot_top_edge + 0.025
            svg.rect \
                x: ratio_to_x(item_center_x - 0.5 * top_legend_box_width),
                y: ratio_to_y(item_center_y - 0.5 * top_legend_box_height),
                width: ratio_to_x(top_legend_box_width),
                height: ratio_to_y(top_legend_box_height),
                fill: ruby_config_bar_colour[ruby_configs[config_idx]],
                stroke: legend_box_stroke_colour
            svg.text @configs_with_human_names[config_idx][0],
                x: ratio_to_x(item_center_x), y: ratio_to_y(item_center_y + 0.5 * top_legend_text_height),
                font_size: font_size,
                text_anchor: "middle",
                font_weight: "bold",
                fill: text_colour
        end


        # Okay. Now let's plot a lot of boxes and whiskers.
        benchmarks.each.with_index do |bench_name, bench_short_idx|
            bench_idx = @benchmark_names.index(bench_name)

            no_jit_mean = @mean_by_config[@no_jit_config][bench_idx]

            bars_width_start = bench_left_edge[bench_short_idx]
            ruby_configs.each.with_index do |config, config_idx|
                human_name = ruby_human_names[config_idx]

                if config == @no_jit_config
                    speedup = 1.0 # No-JIT is always exactly 1x No-JIT
                    rsd_pct = @rsd_pct_by_config[@no_jit_config][bench_idx]
                else
                    speedup, rsd_pct = @speedup_by_config[config][bench_idx]
                end
                rsd_ratio = rsd_pct / 100.0
                bar_height_ratio = speedup / max_speedup_ratio

                # The calculated number is rel stddev and is scaled by bar height.
                stddev_ratio = bar_height_ratio * rsd_ratio

                bar_left = bars_width_start + config_idx * bar_width
                bar_right = bar_left + bar_width
                bar_lr_center = bar_left + 0.5 * bar_width
                bar_top = plot_effective_top + (1.0 - bar_height_ratio) * plot_effective_height
                svg.rect \
                    x: ratio_to_x(bar_left),
                    y: ratio_to_y(bar_top),
                    width: ratio_to_x(bar_width),
                    height: ratio_to_y(bar_height_ratio * plot_effective_height),
                    fill: ruby_config_bar_colour[config],
                    data_tooltip: "#{"%.1f" % speedup}x No-JIT time (#{human_name})"

                # Whiskers should be centered around the top of the bar, at a distance of one stddev.
                top_whisker_y = bar_top - stddev_ratio * plot_effective_height
                svg.line x1: ratio_to_x(bar_left), y1: ratio_to_y(top_whisker_y),
                    x2: ratio_to_x(bar_right), y2: ratio_to_y(top_whisker_y),
                    stroke: axis_colour
                bottom_whisker_y = bar_top + stddev_ratio * plot_effective_height
                svg.line x1: ratio_to_x(bar_left), y1: ratio_to_y(bottom_whisker_y),
                    x2: ratio_to_x(bar_right), y2: ratio_to_y(bottom_whisker_y),
                    stroke: axis_colour
                svg.line x1: ratio_to_x(bar_lr_center), y1: ratio_to_y(top_whisker_y),
                    x2: ratio_to_x(bar_lr_center), y2: ratio_to_y(bottom_whisker_y),
                    stroke: axis_colour
            end

            # Below all the bars, we'll want a tick on the bottom axis and a name of the benchmark
            bars_width_middle = bars_width_start + 0.5 * each_bench_width
            svg.line x1: ratio_to_x(bars_width_middle), y1: ratio_to_y(plot_bottom_edge),
                x2: ratio_to_x(bars_width_middle), y2: ratio_to_y(plot_bottom_edge + tick_length),
                stroke: axis_colour

            text_end_x = bars_width_middle
            text_end_y = plot_bottom_edge + tick_length * 3
            svg.text bench_name.gsub(/\.rb$/, ""),
                x: ratio_to_x(text_end_x),
                y: ratio_to_y(text_end_y),
                fill: text_colour,
                font_size: font_size,
                font_family: "monospace",
                font_weight: "bold",
                text_anchor: "end",
                transform: "rotate(-60, #{ratio_to_x(text_end_x)}, #{ratio_to_y(text_end_y)})"
        end

        svg
    end

    def speedup_tripwires
        tripwires = {}
        @benchmark_names.each_with_index do |bench_name, idx|
            tripwires[bench_name] = {
                mean: @mean_by_config[@with_yjit_config][idx],
                rsd_pct: @rsd_pct_by_config[@with_yjit_config][idx]
            }
        end
        tripwires
    end

    def write_file(filename)
        require "victor"

        real_bench = realish_benchmarks
        synth_bench = @benchmark_names - real_bench

        if real_bench.empty?
            puts "Warning: when writing file #{filename.inspect}, real benchmark list is empty!"
        end
        if synth_bench.empty?
            puts "Warning: when writing file #{filename.inspect}, synthetic benchmark list is empty!"
        end

        @svg_real = svg_object(benchmarks: real_bench) unless real_bench.empty?
        @svg_synth = svg_object(benchmarks: synth_bench) unless synth_bench.empty?
        @svg_everything = svg_object # All the benchmarks

        # Write SVG files for the graphs
        File.open(filename + ".svg", "w") { |f| f.write(@svg_everything.render) }
        File.open(filename + ".real.svg", "w") { |f| f.write(@svg_real.render) } if @svg_real
        File.open(filename + ".synth.svg", "w") { |f| f.write(@svg_synth.render) } if @svg_synth

        # First the 'regular' details report, with tables and text descriptions
        script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_speed_details.html.erb")
        html_output = script_template.result(binding)
        File.open(filename + ".html", "w") { |f| f.write(html_output) }

        # And then the "no normal person would ever care" details report, with raw everything
        script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_speed_raw_details.html.erb")
        html_output = script_template.result(binding)
        File.open(filename + ".raw_details.html", "w") { |f| f.write(html_output) }

        json_data = speedup_tripwires
        File.open(filename + ".tripwires.json", "w") { |f| f.write JSON.pretty_generate json_data }

        #write_to_csv(filename + ".csv", [@headings] + report_table_data)
    end

end

# This very small report is to give the quick headlines and summary for a YJIT comparison.
class YJITMetrics::SpeedHeadlineReport < YJITMetrics::BloggableSingleReport
    def self.report_name
        "blog_speed_headline"
    end

    def format_speedup(ratio)
        if ratio >= 1.01
            "%.1f%% faster" % ((ratio - 1.0) * 100)
        elsif ratio < 0.99
            "%.1f%% slower" % ((1.0 - ratio) * 100)
        else
            "the same speed" # Grammar's not perfect here
        end
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the parent class, look up relevant data
        super

        look_up_data_by_ruby

        # Sort benchmarks by most-to-least real, and then alphabetically
        @benchmark_names.sort_by! { |bench_name| [ -BENCHMARK_METADATA[bench_name][:realness], bench_name ] }

        calc_stats_by_config

        # "Ratio of total times" method
        #@yjit_vs_cruby_ratio = @total_time_by_config[@no_jit_config] / @total_time_by_config[@with_yjit_config]
        #@yjit_vs_mjit_ratio = @total_time_by_config[@with_mjit_config] / @total_time_by_config[@with_yjit_config]

        # Scale "realish" benchmarks to normalised No-JIT time and average that way, so each benchmark is weighted equally
        realish_runtimes = realish_benchmarks.map do |bench_name|
            bench_idx = @benchmark_names.index(bench_name)

            bench_no_jit_mean = @mean_by_config[@no_jit_config][bench_idx]
            bench_yjit_mean = @mean_by_config[@with_yjit_config][bench_idx]
            bench_mjit_mean = @mean_by_config[@with_mjit_config][bench_idx]

            [ bench_yjit_mean, bench_mjit_mean, bench_no_jit_mean ]
        end
        # Normalized-per-bench real-bench-only method
        @yjit_vs_cruby_ratio = realish_runtimes.map { |yjit_mean, _, no_jit_mean| no_jit_mean / yjit_mean }.sum / realish_runtimes.size
        @yjit_vs_mjit_ratio = realish_runtimes.map { |yjit_mean, mjit_mean, _| mjit_mean / yjit_mean }.sum / realish_runtimes.size

        @railsbench_idx = @benchmark_names.index("railsbench")
        if @railsbench_idx
            @yjit_vs_cruby_railsbench_ratio = @mean_by_config[@no_jit_config][@railsbench_idx] / @mean_by_config[@with_yjit_config][@railsbench_idx]
            @yjit_vs_mjit_railsbench_ratio = @mean_by_config[@with_mjit_config][@railsbench_idx] / @mean_by_config[@with_yjit_config][@railsbench_idx]
        end
    end

    def to_s
        script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_speed_headline.html.erb")
        script_template.result(binding) # Evaluate an Erb template with template_settings
    end

    def write_file(filename)
        html_output = self.to_s
        File.open(filename + ".html", "w") { |f| f.write(html_output) }
    end
end
