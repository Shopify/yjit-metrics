# frozen_string_literal: true

require_relative "../report"

module YJITMetrics
  # This is intended to show the total time taken to get to
  # a particular iteration, to help understand warmup
  class TotalToIterReport < Report
    def self.report_name
      "total_to_iter"
    end

    def initialize(config_names, results, benchmarks: [])
      raise "Not yet updated for multi-platform!"

      super

      @headings_by_config = {}
      @col_formats_by_config = {}
      @report_data_by_config = {}

      @config_names.each do |config|
        times = @result_set.times_for_config_by_benchmark(config, in_runs: true)
        warmups = @result_set.warmups_for_config_by_benchmark(config, in_runs: true)

        # Combine times and warmups for each run, for each benchmark
        all_iters = {}
        times.keys.each do |benchmark_name|
          all_iters[benchmark_name] = warmups[benchmark_name].zip(times[benchmark_name]).map { |warmups, real_iters| warmups + real_iters }
        end

        benchmark_names = filter_benchmark_names(times.keys)
        raise "No benchmarks found for config #{config.inspect}!" if benchmark_names.empty?
        max_num_runs = benchmark_names.map { |bn| times[bn].size }.max

        # For every benchmark, check the fewest iterations/run.
        min_iters_per_benchmark = benchmark_names.map { |bn| all_iters[bn].map { |run| run.size }.min }

        most_cols_of_benchmarks = min_iters_per_benchmark.max

        showcased_iters = [1, 5, 10, 50, 100, 200, 500, 1000, 5000, 10_000, 50_000, 100_000].select { |i| i <= most_cols_of_benchmarks }

        @headings_by_config[config] =
          [ "bench", "samples" ] +
          showcased_iters.map { |iter| "iter ##{iter}" } +
          showcased_iters.map { |iter| "RSD ##{iter}" }
        @col_formats_by_config[config] =
          [ "%s", "%d" ] +
          showcased_iters.map { "%.1fms" } +
          showcased_iters.map { "%.2f%%" }
        @report_data_by_config[config] = []

        benchmark_names.each do |benchmark_name|
          # We assume that for each config/benchmark combo we have the same number of warmup runs as timed runs
          all_runs = all_iters[benchmark_name]
          num_runs = all_runs.size
          min_iters = all_runs.map { |run| run.size }.min

          iters_present = showcased_iters.select { |i| i <= min_iters }
          end_nils = [nil] * (showcased_iters.size - iters_present.size)

          iter_N_mean = []
          iter_N_rsd = []

          iters_present.each do |iter_num|
            # For this report, we want the *total* non-harness time to get to an iteration number
            iter_series = all_runs.map { |run| (0..(iter_num - 1)).map { |idx| run[idx] }.sum }
            iter_N_mean.push mean(iter_series)
            iter_N_rsd.push rel_stddev_pct(iter_series)
          end

          @report_data_by_config[config].push([benchmark_name, num_runs] + iter_N_mean + end_nils + iter_N_rsd + end_nils)
        end
      end
    end

    def to_s
      output = ""

      @config_names.each do |config_name|
        output.concat("Total Time to Iteration N for #{config_name.capitalize}:\n\n")

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
end
