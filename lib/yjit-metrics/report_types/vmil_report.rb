require_relative "yjit_stats_reports"

# This report is to compare YJIT's time-in-JIT versus its speedup for various benchmarks.
class YJITMetrics::VMILReport < YJITMetrics::YJITStatsReport
    def exactly_one_config_with_name(configs, substring, description)
        matching_configs = configs.select { |name| name.include?(substring) }
        raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
        raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty?
        matching_configs[0]
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the YJIT stats parent class
        super

        @with_yjit_config = exactly_one_config_with_name(config_names, "with_yjit", "with-YJIT")
        @with_mjit_config = exactly_one_config_with_name(config_names, "with_mjit", "with-MJIT")
        @no_jit_config    = exactly_one_config_with_name(config_names, "no_jit", "no-JIT")

        # Grab relevant data from the ResultSet
        times_by_config = {}
        [ @with_yjit_config, @with_mjit_config, @no_jit_config ].each { |config| times_by_config[config] = results.times_for_config_by_benchmark(config) }
        times_by_config.each do |config_name, results|
            raise("No results for configuration #{config_name.inspect} in PerBenchRubyComparison!") if results.nil? || results.empty?
        end
        stats = results.yjit_stats_for_config_by_benchmark(@stats_config)

        # Only run benchmarks if there is no list of "only run these" benchmarks, or if the benchmark name starts with one of the list elements
        @benchmark_names = times_by_config[@no_jit_config].keys
        unless benchmarks.empty?
            @benchmark_names.select! { |bench_name| benchmarks.any? { |bench_spec| bench_name.start_with?(bench_spec) }}
        end

        # Sort benchmarks by compiled ISEQ count
        @benchmark_names.sort_by! { |bench_name| stats[bench_name]["compiled_iseq_count"] }

        # Report contents
        @headings = [ "bench", "YJIT (ms)", "YJIT rel stddev (%)" "MJIT (ms)", "MJIT rel stddev (%)", "No JIT (ms)", "No JIT rel stddev (%)" "YJIT speedup (%)", "MJIT speedup (%)", "% in YJIT" ]
        @col_formats = [ "%s" ] + [ "%.1f", "%.2f" ] * 3 + [ "%.2f", "%.2f", "%.2f" ]

        @report_data = @benchmark_names.map do |benchmark_name|
            no_jit_config_times = times_by_config[@no_jit_config][benchmark_name]
            no_jit_mean = mean(no_jit_config_times)
            no_jit_stddev = stddev(no_jit_config_times)
            no_jit_rel_stddev = no_jit_stddev / no_jit_mean

            with_mjit_config_times = times_by_config[@with_mjit_config][benchmark_name]
            with_mjit_mean = mean(with_mjit_config_times)
            with_mjit_stddev = stddev(with_mjit_config_times)
            with_mjit_rel_stddev = with_mjit_stddev / with_mjit_mean

            with_yjit_config_times = times_by_config[@with_yjit_config][benchmark_name]
            with_yjit_mean = mean(with_yjit_config_times)
            with_yjit_stddev = stddev(with_yjit_config_times)
            with_yjit_rel_stddev = with_yjit_stddev / with_yjit_mean

            mjit_speedup_ratio = no_jit_mean / with_mjit_mean
            mjit_speedup_pct = (mjit_speedup_ratio - 1.0) * 100.0
            mjit_speedup_rel_stddev = Math.sqrt((no_jit_rel_stddev * no_jit_rel_stddev) + (with_mjit_rel_stddev * with_mjit_rel_stddev))

            yjit_speedup_ratio = no_jit_mean / with_yjit_mean
            yjit_speedup_pct = (yjit_speedup_ratio - 1.0) * 100.0
            yjit_speedup_rel_stddev = Math.sqrt((no_jit_rel_stddev * no_jit_rel_stddev) + (with_yjit_rel_stddev * with_yjit_rel_stddev))

            # A benchmark run may well return multiple sets of YJIT stats per benchmark name/type.
            # For these calculations we just add all relevant counters together.
            this_bench_stats = combined_stats_data_for_benchmarks([benchmark_name])

            total_exits = total_exit_count(this_bench_stats)
            retired_in_yjit = this_bench_stats["exec_instruction"] - total_exits
            total_insns_count = retired_in_yjit + this_bench_stats["vm_insns_count"]
            yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count

            [ benchmark_name,
                with_yjit_mean, with_yjit_rel_stddev,
                with_mjit_mean, with_mjit_rel_stddev,
                no_jit_mean, no_jit_rel_stddev,
                yjit_speedup_pct, mjit_speedup_pct, yjit_ratio_pct ]
        end
    end

    def to_s
        format_as_table(@headings, @col_formats, @report_data)
    end

    def write_file(filename)
        write_to_csv(filename + ".csv", @headings + @report_data)
    end

end
