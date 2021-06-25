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

# Encapsulate multiple benchmark runs across multiple Ruby versions.
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
        @benchmark_metadata = {}
        @ruby_metadata = {}
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
    # Note that this doesn't track "batches" of runs, such as when restarting
    # the benchmark and doing, say, 10 batches of 30. Instead, if they're added
    # via 30 calls to the method below, they will be combined into a single
    # array of 300 measurements.
    #
    # Every benchmark run is assumed to come with a corresponding metadata hash
    # and (optional) hash of YJIT stats. However, there should normally only
    # be one set of Ruby metadata, not one per benchmark run.
    def add_for_ruby(ruby_name, benchmark_results)
        @times[ruby_name] ||= {}
        benchmark_results["times"].each do |benchmark_name, times|
            @times[ruby_name][benchmark_name] ||= []
            @times[ruby_name][benchmark_name].concat(times)
        end

        @benchmark_metadata[ruby_name] ||= {}
        benchmark_results["benchmark_metadata"].each do |benchmark_name, metadata_array|
            @benchmark_metadata[ruby_name][benchmark_name] ||= []
            @benchmark_metadata[ruby_name][benchmark_name].concat(metadata_array)
        end

        @ruby_metadata[ruby_name] ||= benchmark_results["ruby_metadata"]
        if @ruby_metadata[ruby_name] != benchmark_results["ruby_metadata"]
            print "Ruby metadata is meant to *only* include information that should always be\n" +
              "  the same for the same Ruby executable. Please verify that you have not added\n" +
              "  inappropriate Ruby metadata or accidentally used the same name for two\n"
              "  different Ruby executables.\n"
            raise "Ruby metadata does not match for same Ruby name!"
        end

        @yjit_stats[ruby_name] ||= {}
        benchmark_results["yjit_stats"].each do |benchmark_name, stats_array|
            @yjit_stats[ruby_name][benchmark_name] ||= []
            @yjit_stats[ruby_name][benchmark_name].concat(stats_array)
        end
    end

    def times_for_ruby_by_benchmark(ruby)
        @times[ruby]
    end

    # Output a CSV file which contains metadata as key/value pairs, followed by a blank row, followed by the raw time data
    def to_csv
        output_rows = @metadata.keys.zip(@metadata.values)
        output_rows << []
        output_rows.concat(@data)

        csv_out = ""
        csv = CSV.new(csv_out)
        output_rows.each { |row| csv << row }
        csv_out
    end
end

# We'd like to be able to create a quick columnar report, often for one
# Ruby versus another, and load/dump it as JSON or CSV. This isn't a
# report class that is all things to all people -- it's specifically
# a comparison of two or more Rubies per-benchmark for yjit-bench.
#
# The first Ruby version given is assumed to be the baseline against
# which the other Rubies are measured.
class YJITMetrics::PerBenchRubyComparison
    def initialize(ruby_names, results)
        @ruby_names = ruby_names
        @result_set = results

        @headings = [ "bench" ] + ruby_names.flat_map { |ruby| [ "#{ruby} (ms)", "rel stddev (%)" ] } + alt_rubies.map { |ruby| "#{ruby}/#{base_ruby}" }
        @col_formats = [ "%s" ] + ruby_names.flat_map { [ "%.1f", "%.1f" ] } + alt_rubies.map { "%.2f" }

        @report_data = []
        times_by_ruby = ruby_names.map { |ruby| results.times_for_ruby_by_benchmark(ruby) }
        benchmark_names = times_by_ruby[base_ruby].keys

        benchmark_names.each do |benchmark_name|
            row = [ benchmark_name ]
            ruby_names.each do |ruby|
                ruby_times = times_by_ruby[ruby][benchmark_name]
                ruby_mean = mean(ruby_times)
                row.push ruby_mean
                row.push 100.0 * stddev(ruby_times) / ruby_mean
            end

            base_ruby_mean = mean(times_by_ruby[base_ruby][benchmark_name])
            alt_rubies.each do |ruby|
                ruby_mean = mean(times_by_ruby[ruby][benchmark_name])
                row.push ruby_mean / base_ruby_mean
            end

            @report_data.push row
        end
    end

    def base_ruby
        @ruby_names[0]
    end

    def alt_rubies
        @ruby_names[1..-1]
    end

    def write_to_csv(filename)
        CSV.open(filename, "wb") do |csv|
            csv << @headings
            @report_data.each { |row| csv << row }
        end
    end

    def as_text_table
        out = ""

        num_cols = @report_data[0].length

        col_widths = (0...num_cols).map do |col_num|
            @report_data.map { |row| row[col_num].length }.max
        end

        separator = col_widths.map { |width| "-" * width }.join("  ")
        out.concat(separator + "\n")

        @report_data.each do |row|
            row_data = @col_formats.zip(row).map { |fmt, data| fmt % data }
            out.concat(row_data.join("  ") + "\n")
        end

        out.concat(separator + "\n")
        out.concat(ruby_legend_text)
    end

    def ruby_legend_text
        "Legend:\n" +
        alt_rubies.map do |ruby|
            "- #{ruby}/#{base_ruby}: ratio of mean(#{ruby} times)/mean(#{base_ruby} times). >1 means #{base_ruby} is faster.\n"
        end
    end
end
