require_relative "yjit_stats_reports"

class YJITMetrics::VMILReport < YJITMetrics::YJITStatsReport
    def exactly_one_config_with_name(configs, substring, description)
        matching_configs = configs.select { |name| name.include?(substring) }
        raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
        raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty?
        matching_configs[0]
    end

    def look_up_vmil_data(in_batches: false)
        @with_yjit_config = exactly_one_config_with_name(@config_names, "with_yjit", "with-YJIT")
        @with_mjit_config = exactly_one_config_with_name(@config_names, "with_mjit", "with-MJIT")
        @no_jit_config    = exactly_one_config_with_name(@config_names, "no_jit", "no-JIT")

        # Grab relevant data from the ResultSet
        @times_by_config = {}
        @warmups_by_config = {}
        [ @with_yjit_config, @with_mjit_config, @no_jit_config ].each do|config|
            @times_by_config[config] = @results.times_for_config_by_benchmark(config, in_batches: in_batches)
            @warmups_by_config[config] = @results.warmups_for_config_by_benchmark(config, in_batches: in_batches)
        end
        @times_by_config.each do |config_name, config_results|
            raise("No results for configuration #{config_name.inspect} in #{self.class}!") if config_results.nil? || config_results.empty?
            # No warmups for a given configuration is fine, and quite normal for the VMIL warmups report.
        end
        @yjit_stats = @results.yjit_stats_for_config_by_benchmark(@stats_config, in_batches: in_batches)

        # Only run benchmarks if there is no list of "only run these" benchmarks, or if the benchmark name starts with one of the list elements
        @benchmark_names = @times_by_config[@no_jit_config].keys
        unless @benchmarks.empty?
            @benchmark_names.select! { |bench_name| benchmarks.any? { |bench_spec| bench_name.start_with?(bench_spec) }}
        end
    end

end

# This report is to compare YJIT's time-in-JIT versus its speedup for various benchmarks.
class YJITMetrics::VMILSpeedReport < YJITMetrics::VMILReport
    def initialize(config_names, results, benchmarks: [])
        # Set up the YJIT stats parent class
        super

        look_up_vmil_data

        # Sort benchmarks by compiled ISEQ count
        @benchmark_names.sort_by! { |bench_name| @yjit_stats[bench_name][0]["compiled_iseq_count"] }

        # Report contents
        @headings = [ "bench", "YJIT (ms)", "YJIT rel stddev (%)", "MJIT (ms)", "MJIT rel stddev (%)", "No JIT (ms)", "No JIT rel stddev (%)", "YJIT speedup (%)", "YJIT speedup stddev (%)", "MJIT speedup (%)", "MJIT speedup stddev (%)", "% in YJIT" ]
        @col_formats = [ "%s" ] + [ "%.1f", "%.2f" ] * 3 + [ "%.2f", "%.2f", "%.2f", "%.2f", "%.2f" ]

        @report_data = @benchmark_names.map do |benchmark_name|
            no_jit_config_times = @times_by_config[@no_jit_config][benchmark_name]
            no_jit_mean = mean(no_jit_config_times)
            no_jit_stddev = stddev(no_jit_config_times)
            no_jit_rel_stddev = no_jit_stddev / no_jit_mean
            no_jit_rel_stddev_pct = no_jit_rel_stddev * 100.0

            with_mjit_config_times = @times_by_config[@with_mjit_config][benchmark_name]
            with_mjit_mean = mean(with_mjit_config_times)
            with_mjit_stddev = stddev(with_mjit_config_times)
            with_mjit_rel_stddev = with_mjit_stddev / with_mjit_mean
            with_mjit_rel_stddev_pct = with_mjit_rel_stddev * 100.0

            with_yjit_config_times = @times_by_config[@with_yjit_config][benchmark_name]
            with_yjit_mean = mean(with_yjit_config_times)
            with_yjit_stddev = stddev(with_yjit_config_times)
            with_yjit_rel_stddev = with_yjit_stddev / with_yjit_mean
            with_yjit_rel_stddev_pct = with_yjit_rel_stddev * 100.0

            mjit_speedup_ratio = no_jit_mean / with_mjit_mean
            mjit_speedup_pct = (mjit_speedup_ratio - 1.0) * 100.0
            mjit_speedup_rel_stddev = Math.sqrt((no_jit_rel_stddev * no_jit_rel_stddev) + (with_mjit_rel_stddev * with_mjit_rel_stddev))
            mjit_speedup_rel_stddev_pct = mjit_speedup_rel_stddev * 100.0

            yjit_speedup_ratio = no_jit_mean / with_yjit_mean
            yjit_speedup_pct = (yjit_speedup_ratio - 1.0) * 100.0
            yjit_speedup_rel_stddev = Math.sqrt((no_jit_rel_stddev * no_jit_rel_stddev) + (with_yjit_rel_stddev * with_yjit_rel_stddev))
            yjit_speedup_rel_stddev_pct = yjit_speedup_rel_stddev * 100.0

            # A benchmark run may well return multiple sets of YJIT stats per benchmark name/type.
            # For these calculations we just add all relevant counters together.
            this_bench_stats = combined_stats_data_for_benchmarks([benchmark_name])

            total_exits = total_exit_count(this_bench_stats)
            retired_in_yjit = this_bench_stats["exec_instruction"] - total_exits
            total_insns_count = retired_in_yjit + this_bench_stats["vm_insns_count"]
            yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count

            [ benchmark_name,
                with_yjit_mean, with_yjit_rel_stddev_pct,
                with_mjit_mean, with_mjit_rel_stddev_pct,
                no_jit_mean, no_jit_rel_stddev_pct,
                yjit_speedup_pct, yjit_speedup_rel_stddev_pct,
                mjit_speedup_pct, mjit_speedup_rel_stddev_pct,
                yjit_ratio_pct ]
        end
    end

    def to_s
        format_as_table(@headings, @col_formats, @report_data)
    end

    def write_file(filename)
        write_to_csv(filename + ".csv", [@headings] + @report_data)
    end

end

# This report intends to compare YJIT warmup vs CRuby (no JIT) vs MJIT
# TODO: TruffleRuby warmup
class YJITMetrics::VMILWarmupReport < YJITMetrics::VMILReport
    def initialize(config_names, results, benchmarks: [])
        require "victor" # This report uses the Victor SVG generator

        # Set up the YJIT stats parent class
        super

        look_up_vmil_data(in_batches: true)

        # Report contents
        @headings = [ "bench" ]
        @col_formats = [ "%s" ]

        @benchmark_names.map do |benchmark_name|
            [["YJIT", @with_yjit_config],
             ["MJIT", @with_mjit_config],
             ["No JIT", @no_jit_config]].each do |human_name, config_name|

                config_data = @times_by_config[config_name][benchmark_name].select { |run| !run.empty? }

                # The warmup report assumes data uses no warmup iterations, only "real" iterations
                num_batches = config_data.size
                num_iters = config_data[0].size

                unless config_data.all? { |batch| batch.size == num_iters }
                    raise "Not all runs are #{num_iters} iterations for #{human_name}!"
                end

                STDERR.puts "#{num_batches} runs, #{num_iters} iters/run"
            end
        end
    end

    def to_s
    end
end
