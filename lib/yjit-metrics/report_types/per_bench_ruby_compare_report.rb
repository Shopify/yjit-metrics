# We'd like to be able to create a quick columnar report, often for one
# Ruby config versus another, and load/dump it as JSON or CSV. This isn't a
# report class that is all things to all people -- it's specifically
# a comparison of two or more configurations per-benchmark for yjit-bench.
#
# The first configuration given is assumed to be the baseline against
# which the other configs are measured.
class YJITMetrics::PerBenchRubyComparison < YJITMetrics::Report
    def initialize(config_names, results, benchmarks: [])
        raise "No Rubies specified!" if config_names.empty?

        bad_configs = config_names - results.available_configs
        raise "Unknown configurations in report: #{bad_configs.inspect}!" unless bad_configs.empty?

        @config_names = config_names
        @only_benchmarks = benchmarks
        @result_set = results

        @headings = [ "bench" ] + config_names.flat_map { |config| [ "#{config} (ms)", "rel stddev (%)" ] } + alt_configs.map { |config| "#{config}/#{base_config}" }
        @col_formats = [ "%s" ] + config_names.flat_map { [ "%.1f", "%.1f" ] } + alt_configs.map { "%.2f" }

        @report_data = []
        times_by_config = {}
        config_names.each { |config| times_by_config[config] = results.times_for_config_by_benchmark(config) }

        benchmark_names = times_by_config[config_names[0]].keys

        times_by_config.each do |config_name, results|
            raise("No results for configuration #{config_name.inspect} in PerBenchRubyComparison!") if results.nil?
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

    def base_config
        @config_names[0]
    end

    def alt_configs
        @config_names[1..-1]
    end

    def write_to_csv(filename)
        CSV.open(filename, "wb") do |csv|
            csv << @headings
            @report_data.each { |row| csv << row }
        end
    end

    def to_s
        format_as_table(@headings, @col_formats, @report_data) + config_legend_text
    end

    def config_legend_text
        "\nLegend:\n" +
        alt_configs.map do |config|
            "- #{config}/#{base_config}: ratio of mean(#{config} times)/mean(#{base_config} times). >1 means #{base_config} is faster.\n"
        end.join + "\n"
    end
end
