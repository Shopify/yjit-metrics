# Make sure YJITMetrics namespace is declared
module YJITMetrics; end

# Statistical methods
module YJITMetrics::Stats
    def mean(values)
        return values.sum(0.0) / values.size
    end

    def stddev(values)
        xbar = mean(values)
        diff_sqrs = values.map { |v| (v-xbar)*(v-xbar) }
        # Bessel's correction requires dividing by length - 1, not just length:
        # https://en.wikipedia.org/wiki/Standard_deviation#Corrected_sample_standard_deviation
        variance = diff_sqrs.sum(0.0) / (values.length - 1)
        return Math.sqrt(variance)
    end
end

# Encapsulate multiple benchmark runs across multiple Ruby configurations.
# Do simple calculations, reporting and file I/O.
#
# Note that a JSON file with many results can be quite large.
# Normally it's appropriate to store raw data as multiple JSON files
# that contain one set of runs each. Large multi-Ruby datasets
# may not be practical to save as full raw data.
class YJITMetrics::ResultSet
    include YJITMetrics::Stats

    def initialize
        @times = {}
        @warmups = {}
        @benchmark_metadata = {}
        @ruby_metadata = {}
        @yjit_stats = {}
    end

    # A ResultSet normally expects to see results with this structure:
    #
    # {
    #   "times" => { "benchname1" => [ 11.7, 14.5, 16.7, ... ], "benchname2" => [...], ... },
    #   "benchmark_metadata" => { "benchname1" => {...}, "benchname2" => {...}, ... },
    #   "ruby_metadata" => {...},
    #   "yjit_stats" => { "benchname1" => [{...}, {...}...], "benchname2" => [{...}, {...}, ...] }
    # }
    #
    # Note that this structure doesn't represent "batches" of runs, such as when restarting
    # the benchmark and doing, say, 10 batches of 30. Instead they should be added
    # via 30 calls to the method below, they will be combined into a single
    # array of 300 measurements.
    #
    # Every benchmark run is assumed to come with a corresponding metadata hash
    # and (optional) hash of YJIT stats. However, there should normally only
    # be one set of Ruby metadata, not one per benchmark run.
    def add_for_config(config_name, benchmark_results)
        @times[config_name] ||= {}
        benchmark_results["times"].each do |benchmark_name, times|
            @times[config_name][benchmark_name] ||= []
            @times[config_name][benchmark_name].concat(times)
        end

        @warmups[config_name] ||= {}
        (benchmark_results["warmups"] || {}).each do |benchmark_name, warmups|
            @times[config_name][benchmark_name] ||= []
            @times[config_name][benchmark_name].concat(warmups)
        end

        @benchmark_metadata[config_name] ||= {}
        benchmark_results["benchmark_metadata"].each do |benchmark_name, metadata_for_benchmark|
            @benchmark_metadata[config_name][benchmark_name] ||= metadata_for_benchmark
            if @benchmark_metadata[config_name][benchmark_name] != metadata_for_benchmark
                STDERR.puts "WARNING: multiple benchmark runs of #{benchmark_name} in #{config_name} have different benchmark metadata!"
            end
        end

        @ruby_metadata[config_name] ||= benchmark_results["ruby_metadata"]
        if @ruby_metadata[config_name] != benchmark_results["ruby_metadata"]
            print "Ruby metadata is meant to *only* include information that should always be\n" +
              "  the same for the same Ruby executable. Please verify that you have not added\n" +
              "  inappropriate Ruby metadata or accidentally used the same name for two\n" +
              "  different Ruby executables.\n"
            raise "Ruby metadata does not match for same configuration name!"
        end

        @yjit_stats[config_name] ||= {}
        benchmark_results["yjit_stats"].each do |benchmark_name, stats_array|
            @yjit_stats[config_name][benchmark_name] ||= []
            @yjit_stats[config_name][benchmark_name].concat(stats_array)
        end
    end

    # This returns a hash-of-arrays by configuration name
    # containing benchmark results (times) per
    # benchmark for the specified config.
    def times_for_config_by_benchmark(config)
        raise("No results for configuration: #{config.inspect}!") if !@times.has_key?(config) || @times[config].empty?
        @times[config]
    end

    # This returns a hash-of-arrays by configuration name
    # containing warmup results (times) per
    # benchmark for the specified config.
    def warmups_for_config_by_benchmark(config)
        @warmups[config]
    end

    # This returns a hash-of-hashes by config name
    # containing YJIT statistics, if gathered, per
    # benchmark for the specified config. For configs
    # that don't collect YJIT statistics, the inner
    # hash will be empty.
    def yjit_stats_for_config_by_benchmark(config)
        @yjit_stats[config]
    end

    # This returns a hash-of-hashes by config name
    # containing per-benchmark metadata (parameters) per
    # benchmark for the specified config.
    def benchmark_metadata_for_config_by_benchmark(config)
        @benchmark_metadata[config]
    end

    # This returns a hash of metadata for the given config name
    def metadata_for_config(config)
        @ruby_metadata[config]
    end

    # What Ruby configurations does this ResultSet contain data for?
    def available_configs
        @ruby_metadata.keys
    end

    # What Ruby configurations, if any, have YJIT statistics available?
    def configs_containing_yjit_stats
        @yjit_stats.keys.select do |config_name|
            stats = @yjit_stats[config_name]

            !stats.nil? && !stats.empty? && !stats.values.all?(&:empty?)
        end
    end
end

# Shared utility methods for reports
class YJITMetrics::Report
    include YJITMetrics::Stats

    # Take column headings, formats for the percent operator and data, and arrange it
    # into a simple ASCII table returned as a string.
    def format_as_table(headings, col_formats, data, separator_character: "-", column_spacer: "  ")
        out = ""

        num_cols = data[0].length

        formatted_data = data.map.with_index do |row, idx|
            col_formats.zip(row).map { |fmt, data| fmt % data }
        end

        col_widths = (0...num_cols).map { |col_num| (formatted_data.map { |row| row[col_num].length } + [ headings[col_num].length ]).max }

        out.concat(headings.map.with_index { |h, idx| "%#{col_widths[idx]}s" % h }.join(column_spacer), "\n")

        separator = col_widths.map { |width| separator_character * width }.join(column_spacer)
        out.concat(separator, "\n")

        formatted_data.each do |row|
            out.concat (row.map.with_index { |item, idx| " " * (col_widths[idx] - item.size) + item }).join(column_spacer), "\n"
        end

        out.concat("\n", separator, "\n")
    end

    def write_to_csv(filename, data)
        CSV.open(filename, "wb") do |csv|
            data.each { |row| csv << row }
        end
    end

end
