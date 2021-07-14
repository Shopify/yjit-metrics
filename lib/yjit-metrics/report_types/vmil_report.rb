require_relative "yjit_stats_reports"

# This report is to compare YJIT's time-in-JIT versus its speedup for various benchmarks.
class YJITMetrics::VMILReport < YJITMetrics::YJITStatsReport
    def initialize(config_names, results, benchmarks: [])
        # Set up the YJIT stats parent class
        super

        # We've figured out which config is the YJIT stats. Now which one is production stats with YJIT turned on?
        # For now, let's assume it contains the string "with_yjit".
        alt_configs = config_names - [ @stats_config ]
        with_yjit_configs = alt_configs.select { |name| name["with_yjit"] }
        raise "We found more than one candidate with-YJIT config (#{with_yjit_configs.inspect}) in this result set!" if with_yjit_configs.size > 1
        raise "We didn't find any config that looked like a with-YJIT config among #{config_names.inspect}!" if with_yjit_configs.empty?
        @with_yjit_config = with_yjit_configs[0]

        # Now which one has no YJIT? Let's assume it contains the string "no_jit".
        alt_configs -= with_yjit_configs
        no_yjit_configs = alt_configs.select { |name| name["no_jit"] }
        raise "We found more than one candidate no-YJIT config (#{no_yjit_configs.inspect}) in this result set!" if no_yjit_configs.size > 1
        raise "We didn't find any config that looked like a no-YJIT config among #{config_names.inspect}!" if no_yjit_configs.empty?
        @no_yjit_config = no_yjit_configs[0]

        # Let's calculate some report data
        times_by_config = {}
        [ @with_yjit_config, @no_yjit_config ].each { |config| times_by_config[config] = results.times_for_config_by_benchmark(config) }
        @headings = [ "bench", @with_yjit_config + " (ms)", "speedup (%)", "% in YJIT" ]
        @col_formats = [ "%s", "%.1f", "%.2f", "%.2f" ]

        # Only run benchmarks if there is no list of "only run these" benchmarks, or if the benchmark name starts with one of the list elements
        @benchmark_names = times_by_config[@no_yjit_config].keys
        unless benchmarks.empty?
            @benchmark_names.select! { |bench_name| benchmarks.any? { |bench_spec| bench_name.start_with?(bench_spec) }}
        end

        times_by_config.each do |config_name, results|
            raise("No results for configuration #{config_name.inspect} in PerBenchRubyComparison!") if results.nil? || results.empty?
        end

        stats = results.yjit_stats_for_config_by_benchmark(@stats_config)

        @report_data = @benchmark_names.map do |benchmark_name|
            no_yjit_config_times = times_by_config[@no_yjit_config][benchmark_name]
            no_yjit_mean = mean(no_yjit_config_times)
            with_yjit_config_times = times_by_config[@with_yjit_config][benchmark_name]
            with_yjit_mean = mean(with_yjit_config_times)
            yjit_ratio = no_yjit_mean / with_yjit_mean
            yjit_speedup_pct = (yjit_ratio - 1.0) * 100.0

            # A benchmark run may well return multiple sets of YJIT stats per benchmark name/type.
            # For these calculations we just add all relevant counters together.
            this_bench_stats = combined_stats_data_for_benchmarks([benchmark_name])

            total_exits = total_exit_count(this_bench_stats)
            retired_in_yjit = this_bench_stats["exec_instruction"] - total_exits
            total_insns_count = retired_in_yjit + this_bench_stats["vm_insns_count"]
            yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count

            [ benchmark_name, with_yjit_mean, yjit_speedup_pct, yjit_ratio_pct ]
        end
    end

    def to_s
        format_as_table(@headings, @col_formats, @report_data)
    end

end
