# This is intended to be a simple warmup report, showing how long it takes
# one or more Ruby implementations to reach full performance, per-benchmark.
class YJITMetrics::WarmupReport < YJITMetrics::Report
    def initialize(config_names, results, benchmarks: [])
        raise "No Rubies specified!" if config_names.empty?

        bad_configs = config_names - results.available_configs
        raise "Unknown configurations in report: #{bad_configs.inspect}!" unless bad_configs.empty?

        @config_names = config_names
        @only_benchmarks = benchmarks
        @result_set = results

        # Only run benchmarks if there is no list of "only run these" benchmarks, or if the benchmark name starts with one of the list elements
        @benchmark_names = @times_by_config[@with_yjit_config].keys
        unless @only_benchmarks.empty?
            @benchmark_names.select! { |bench_name| @only_benchmarks.any? { |bench_spec| bench_name.start_with?(bench_spec) }}
        end

        @headings_by_config = {}
        @col_formats_by_config = {}
        @report_data_by_config = {}

        @config_names.each do |config|
            times = @results.times_for_config_by_benchmark(config, in_runs: in_runs)
            max_num_runs = @benchmark_names.map { |bn| times[bn].size }.max

            # For every benchmark, check the fewest iterations/run.
            min_iters_per_benchmark = @benchmark_names.map { |bn| times[bn].map { |run| run.size }.min }

            most_cols_of_benchmarks = min_iters_per_benchmark.max

        	showcased_iters = [1, 5, 10, 50, 100, 500, 1000, 5000, 10_000, 50_000, 100_000].select { |i| i <= most_cols_of_benchmarks }

            @headings_by_config[config_name] =
                [ "bench", "samples" ] +
                showcased_iters.map { |iter| "iter ##{iter}" } +
                showcased_iters.map { |iter| "RSD ##{iter}" }
            @col_formats_by_config[config_name] =
                [ "%s", "%d" ] +
                showcased_iters.map { "%.1fms" } +
                showcased_iters.map { "%.2f%%" }
            @report_data_by_config[config_name] = []

        end


        benchmark_names.each do |benchmark_name|
            # Only run benchmarks if there is no list of "only run these" benchmarks, or if the benchmark name starts with one of the list elements
            unless @only_benchmarks.empty?
                next unless @only_benchmarks.any? { |bench_spec| benchmark_name.start_with?(bench_spec) }
            end
            row = [ benchmark_name ]
            config_names.each do |config|
                unless times_by_config[config][benchmark_name]
                    raise("Configuration #{config.inspect} has no results for #{benchmark_name.inspect} even though #{config_names[0]} does in the same dataset!")
                end
                config_times = times_by_config[config][benchmark_name]
                config_mean = mean(config_times)
                row.push config_mean
                row.push 100.0 * stddev(config_times) / config_mean
            end

            base_config_mean = mean(times_by_config[base_config][benchmark_name])
            alt_configs.each do |config|
                config_mean = mean(times_by_config[config][benchmark_name])
                row.push config_mean / base_config_mean
            end

            @report_data.push row
        end
    end

    def to_s
        output = ""

        @config_names.each do |config_name|
            output.concat("Warmup for #{config_name.capitalize}:\n\n")

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
        @config_names.each do |config_name|
            headings = @headings_by_config[config_name]
            report_data = @report_data_by_config[config_name]
            write_to_csv("#{filename}_#{config_name}.csv", [headings] + report_data)
        end
    end


end
