require_relative "yjit_stats_reports"

class YJITMetrics::CompareReport < YJITMetrics::YJITStatsReport
    def exactly_one_config_with_name(configs, substring, description)
        matching_configs = configs.select { |name| name.include?(substring) }
        raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
        raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty?
        matching_configs[0]
    end

    def look_up_data_by_ruby(in_runs: false, no_jit: true, truffle: false)
        @with_yjit_config = exactly_one_config_with_name(@config_names, "with_yjit", "with-YJIT")
        @with_mjit_config = exactly_one_config_with_name(@config_names, "with_mjit", "with-MJIT")
        @no_jit_config    = exactly_one_config_with_name(@config_names, "no_jit", "no-JIT") if no_jit
        @truffle_config    = exactly_one_config_with_name(@config_names, "truffleruby", "Truffle") if truffle

        @configs_with_human_names = [
            ["YJIT", @with_yjit_config],
            ["MJIT", @with_mjit_config],
            ["No-JIT", @no_jit_config],
            #["Truffle", @truffle_config],
        ]

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

        look_up_data_by_ruby(no_jit: true)

        no_stats_benchmarks = @benchmark_names.select { |bench_name| !@yjit_stats[bench_name] || !@yjit_stats[bench_name][0] || @yjit_stats[bench_name][0].empty? }
        unless no_stats_benchmarks.empty?
            raise "No YJIT stats found for benchmarks: #{no_stats_benchmarks.inspect}"
        end

        # Sort benchmarks by compiled ISEQ count
        @benchmark_names.sort_by! { |bench_name| @yjit_stats[bench_name][0]["compiled_iseq_count"] }

        @headings = [ "bench", "YJIT (ms)", "YJIT RSD", "MJIT (ms)", "MJIT RSD", "No JIT (ms)", "No JIT RSD", "YJIT spd", "YJIT spd RSD", "MJIT spd", "MJIT spd RSD", "% in YJIT" ]

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
        @yjit_speed = []
        @mjit_speed = []
        @yjit_ratio = []

        @benchmark_names.each do |benchmark_name|
            no_jit_config_times = @times_by_config[@no_jit_config][benchmark_name]
            no_jit_mean = mean(no_jit_config_times)
            @mean_by_config[@no_jit_config].push no_jit_mean
            no_jit_rel_stddev = rel_stddev(no_jit_config_times)
            no_jit_rel_stddev_pct = rel_stddev_pct(no_jit_config_times)
            @rsd_by_config[@no_jit_config].push no_jit_rel_stddev_pct

            with_mjit_config_times = @times_by_config[@with_mjit_config][benchmark_name]
            with_mjit_mean = mean(with_mjit_config_times)
            @mean_by_config[@with_mjit_config].push with_mjit_mean
            with_mjit_rel_stddev = rel_stddev(with_mjit_config_times)
            with_mjit_rel_stddev_pct = rel_stddev_pct(with_mjit_config_times)
            @rsd_by_config[@with_mjit_config].push with_mjit_rel_stddev_pct

            with_yjit_config_times = @times_by_config[@with_yjit_config][benchmark_name]
            with_yjit_mean = mean(with_yjit_config_times)
            @mean_by_config[@with_yjit_config].push with_yjit_mean
            with_yjit_rel_stddev = rel_stddev(with_yjit_config_times)
            with_yjit_rel_stddev_pct = rel_stddev_pct(with_yjit_config_times)
            @rsd_by_config[@with_yjit_config].push with_yjit_rel_stddev_pct

            # Note: these are currently using the standard "how to propagate stddev over division" calc for stddev.
            # We've talked about expressing them as multiples of no_jit_mean and not using stddev at all.
            mjit_speed_ratio = (no_jit_mean - with_mjit_mean) / no_jit_mean + 1
            mjit_speed_rel_stddev = Math.sqrt((no_jit_rel_stddev * no_jit_rel_stddev) + (with_mjit_rel_stddev * with_mjit_rel_stddev))
            mjit_speed_rel_stddev_pct = mjit_speed_rel_stddev * 100.0
            @mjit_speed.push [ mjit_speed_ratio, mjit_speed_rel_stddev_pct ]

            yjit_speed_ratio = (no_jit_mean - with_yjit_mean) / no_jit_mean + 1
            yjit_speed_rel_stddev = Math.sqrt((no_jit_rel_stddev * no_jit_rel_stddev) + (with_yjit_rel_stddev * with_yjit_rel_stddev))
            yjit_speed_rel_stddev_pct = yjit_speed_rel_stddev * 100.0
            @yjit_speed.push [ yjit_speed_ratio, yjit_speed_rel_stddev_pct ]

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
            [ bench_name,
                @mean_by_config[@with_yjit_config][idx], @rsd_by_config[@with_yjit_config][idx],
                @mean_by_config[@with_mjit_config][idx], @rsd_by_config[@with_mjit_config][idx],
                @mean_by_config[@no_jit_config][idx],    @rsd_by_config[@no_jit_config][idx],
                *@yjit_speed[idx],
                *@mjit_speed[idx],
                @yjit_ratio[idx]
            ]
        end
    end

    def to_s
        col_formats = [ "%s" ] + [ "%.1f", "%.2f%%" ] * 3 + [ "%.2fx", "%.2f%%", "%.2fx", "%.2f%%", "%.2f%%" ]

        configs = @configs_with_human_names.map { |name, config| config }

        format_as_table(@headings, col_formats, report_table_data) +
            "\nRSD is relative standard deviation (stddev / mean), expressed as a percent.\n" +
            "Spd is the speed (iters/second) of the optimised implementation -- 2.0x would be twice as many iters per second.\n"
    end

    def write_file(filename)
        # If we ever actually render a comparative report to file, we'll need victor for SVG output.
        require "victor"

        svg = Victor::SVG.new template: :minimal
        # ...
        @svg_body = svg.render

        script_template = ERB.new File.read(__dir__ + "/../report_templates/compare_speed.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(filename + ".html", "w") { |f| f.write(html_output) }

        write_to_csv(filename + ".csv", [@headings] + report_table_data)
    end

end

# This report intends to compare YJIT warmup vs CRuby (no JIT) vs MJIT vs TruffleRuby
class YJITMetrics::CompareWarmupReport < YJITMetrics::CompareReport
    def self.report_name
        "compare_warmup"
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the YJIT stats parent class
        super

        look_up_data_by_ruby(in_runs: true, no_jit: true, truffle: false)

        # For each "by_config" hash, if we look up a top-level key and it doesn't exist, default it to a new empty hash.
        @headings_by_config = Hash.new { {} }
        @report_data_by_config = Hash.new { {} }
        @col_formats_by_config = Hash.new { {} }

        @configs_with_human_names.each do |human_name, config_name|
            one_config = @times_by_config[config_name]
            max_num_iters = @benchmark_names.map { |bn| one_config[bn].map { |run| run.size }.max }.max
            showcased_iters = [1, 5, 10, 50, 100, 500, 1000, 5000, 10_000, 50_000, 100_000].select { |i| i <= max_num_iters }

            @col_formats_by_config[config_name] =
                [ "%s", "%d" ] +
                showcased_iters.map { "%.1fms" } +
                showcased_iters.map { "%.2f%%" }
            @headings_by_config[config_name] =
                [ "bench", "samples" ] +
                showcased_iters.map { |iter| "iter ##{iter}" } +
                showcased_iters.map { |iter| "RSD ##{iter}" }
            @report_data_by_config[config_name] = []

            @benchmark_names.each do |benchmark_name|
                config_data = @times_by_config[config_name][benchmark_name].select { |run| !run.empty? }
                num_runs = config_data.size
                num_iters = config_data[0].size

                # The warmup report assumes each run uses no warmup iterations, only "real" iterations

                iter_N_mean = []
                iter_N_rsd = []

                # We have "showcased iters" for the number of columns for all benchmarks... But this benchmark
                # may have fewer columns. So we see which columns to include and which to replace with nil based on
                # our current number of iterations.
                included_iters = showcased_iters.select { |i| i <= num_iters }
                end_nils = [ nil ] * (showcased_iters.size - included_iters.size)

                included_iters.each do |iter_num|
                    iter_idx = iter_num - 1  # Human-displayable iteration #7 is array index 6, right?
                    series = config_data.map { |run| run[iter_idx] }

                    # With variable numbers of iterations/run, it's possible to get nils mixed into the series,
                    # which is bad. And we don't want to just use fewer samples and report it as full quality.
                    # So if there are nils in the series we should push nils for the whole iteration.
                    if series.any?(&:nil?)
                        iter_N_mean.push(nil)
                        iter_N_rsd.push(nil)
                    else
                        m = mean(series)
                        iter_N_mean.push m
                        iter_N_rsd.push rel_stddev_pct(series)
                    end
                end
                iter_N_mean += end_nils
                iter_N_rsd += end_nils

                @report_data_by_config[config_name].push([ benchmark_name, num_runs ] + iter_N_mean + iter_N_rsd)
            end
        end
    end

    def to_s
        output = ""

        @configs_with_human_names.each do |human_name, config_name|
            output.concat("#{human_name} Warmup Report:\n\n")

            output.concat(format_as_table(@headings_by_config[config_name],
                @col_formats_by_config[config_name],
                @report_data_by_config[config_name]))

            output.concat("Each iteration is a set of samples of that iteration in a series.\n")
            output.concat("RSD is relative standard deviation - the standard deviation divided by the mean of the series.\n")
            output.concat("Samples is the number of runs (samples taken) for each specific iteration number.\n")
            output.concat("\n\n")
        end

        output
    end

    def write_file(filename)
        @configs_with_human_names.each do |human_name, config_name|
            headings = @headings_by_config[config_name]
            report_data = @report_data_by_config[config_name]
            write_to_csv("#{filename}_#{human_name}.csv", [headings] + report_data)
        end
    end
end
