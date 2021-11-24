# Make sure YJITMetrics namespace is declared
module YJITMetrics; end

# Statistical methods
module YJITMetrics::Stats
    def sum(values)
        return values.sum(0.0)
    end

    def sum_or_nil(values)
        return nil if values.nil?
        sum(values)
    end

    def mean(values)
        return values.sum(0.0) / values.size
    end

    def mean_or_nil(values)
        return nil if values.nil?
        mean(values)
    end

    def geomean(values)
        exponent = 1.0 / values.size
        values.inject(1.0, &:*) ** exponent
    end

    def geomean_or_nil(values)
        return nil if values.nil?
        geomean(values)
    end

    def stddev(values)
        xbar = mean(values)
        diff_sqrs = values.map { |v| (v-xbar)*(v-xbar) }
        # Bessel's correction requires dividing by length - 1, not just length:
        # https://en.wikipedia.org/wiki/Standard_deviation#Corrected_sample_standard_deviation
        variance = diff_sqrs.sum(0.0) / (values.length - 1)
        return Math.sqrt(variance)
    end

    def stddev_or_nil(values)
        return nil if values.nil?
        stddev(values)
    end

    def rel_stddev(values)
        stddev(values) / mean(values)
    end

    def rel_stddev_or_nil(values)
        return nil if values.nil?
        rel_stddev(values)
    end

    def rel_stddev_pct(values)
        100.0 * stddev(values) / mean(values)
    end

    def rel_stddev_pct_or_nil(values)
        return nil if values.nil?
        rel_stddev_pct(values)
    end

    # See https://en.wikipedia.org/wiki/Covariance#Definition and/or
    # https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Covariance (two-pass algorithm)
    def covariance(x, y)
        raise "Trying to take the covariance of two different-sized arrays!" if x.size != y.size

        x_mean = mean(x)
        y_mean = mean(y)

        cov = 0.0
        (0...(x.size)).each do |i|
            cov += (x[i] - x_mean) * (y[i] - y_mean) / x.size
        end

        cov
    end

    # See https://en.wikipedia.org/wiki/Pearson_correlation_coefficient
    # I'm not convinced this is correct. It definitely doesn't match the least-squares correlation coefficient below.
    def pearson_correlation(x, y)
        raise "Trying to take the Pearson correlation of two different-sized arrays!" if x.size != y.size

        ## Some random Ruby guy method
        #xx_prod = x.map { |xi| xi * xi }
        #yy_prod = y.map { |yi| yi * yi }
        #xy_prod = (0...(x.size)).map { |i| x[i] * y[i] }
        #
        #x_sum = x.sum
        #y_sum = y.sum
        #
        #num = xy_prod.sum - (x_sum * y_sum) / x.size
        #den = Math.sqrt(xx_prod.sum - x_sum ** 2.0 / x.size) * (yy_prod.sum - y_sum ** 2.0 / x.size)
        #
        #num/den

        # Wikipedia translation of the definition
        x_mean = mean(x)
        y_mean = mean(y)
        num = (0...(x.size)).map { |i| (x[i] - x_mean) * (y[i] - y_mean) }.sum
        den = Math.sqrt((0...(x.size)).map { |i| (x[i] - x_mean) ** 2.0 }.sum) *
            Math.sqrt((0...(x.size)).map { |i| (y[i] - y_mean) ** 2.0 }.sum)
        num / den
    end

    # See https://mathworld.wolfram.com/LeastSquaresFitting.html
    def least_squares_slope_intercept_and_correlation(x, y)
        raise "Trying to take the least-squares slope of two different-sized arrays!" if x.size != y.size

        x_mean = mean(x)
        y_mean = mean(y)

        xx_sum_of_squares = x.map { |xi| (xi - x_mean)**2.0 }.sum
        yy_sum_of_squares = y.map { |yi| (yi - y_mean)**2.0 }.sum
        xy_sum_of_squares = (0...(x.size)).map { |i| (x[i] - x_mean) * (y[i] - y_mean) }.sum

        slope = xy_sum_of_squares / xx_sum_of_squares
        intercept = y_mean - slope * x_mean

        r_squared = xy_sum_of_squares ** 2.0 / (xx_sum_of_squares * yy_sum_of_squares)

        [slope, intercept, r_squared]
    end

    # code taken from https://github.com/clbustos/statsample/blob/master/lib/statsample/regression/simple.rb#L74
    # (StatSample Ruby gem, simple linear regression.)
    def simple_regression_slope(x, y)
        raise "Trying to take the least-squares slope of two different-sized arrays!" if x.size != y.size

        x_mean = mean(x)
        y_mean = mean(y)

        num = den = 0.0
        (0...x.size).each do |i|
            num += (x[i] - x_mean) * (y[i] - y_mean)
            den += (x[i] - x_mean)**2.0
        end

        slope = num / den
        #intercept = y_mean - slope * x_mean

        slope
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
        @peak_mem = {}
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
    # Note that this input structure doesn't represent runs (subgroups of iterations),
    # such as when restarting the benchmark and doing, say, 10 groups of 300
    # niterations. To represent that, you would call this method 10 times, once per
    # run. Runs will be kept separate internally, but by default are returned as a
    # combined single array.
    #
    # Every benchmark run is assumed to come with a corresponding metadata hash
    # and (optional) hash of YJIT stats. However, there should normally only
    # be one set of Ruby metadata, not one per benchmark run. Ruby metadata is
    # assumed to be constant for a specific compiled copy of Ruby over all runs.
    def add_for_config(config_name, benchmark_results, normalize_bench_names: true)
        if !benchmark_results.has_key?("version")
            puts "No version entry in benchmark results - falling back to version 1 file format."

            benchmark_results["times"].keys.each do |benchmark_name|
                # v1 JSON files are always single-run, so wrap them in a one-element array.
                benchmark_results["times"][benchmark_name] = [ benchmark_results["times"][benchmark_name] ]
                benchmark_results["warmups"][benchmark_name] = [ benchmark_results["warmups"][benchmark_name] ]
                benchmark_results["yjit_stats"][benchmark_name] = [ benchmark_results["yjit_stats"][benchmark_name] ]

                # Various metadata is still in the same format for v2.
            end
        elsif benchmark_results["version"] != 2
            raise "Getting data from JSON in bad format!"
        else
            # JSON file is marked as version 2, so all's well.
        end

        @times[config_name] ||= {}
        benchmark_results["times"].each do |benchmark_name, times|
            benchmark_name = benchmark_name.sub(/.rb$/, "") if normalize_bench_names
            @times[config_name][benchmark_name] ||= []
            @times[config_name][benchmark_name].concat(times)
        end

        @warmups[config_name] ||= {}
        (benchmark_results["warmups"] || {}).each do |benchmark_name, warmups|
            benchmark_name = benchmark_name.sub(/.rb$/, "") if normalize_bench_names
            @warmups[config_name][benchmark_name] ||= []
            @warmups[config_name][benchmark_name].concat(warmups)
        end

        @yjit_stats[config_name] ||= {}
        benchmark_results["yjit_stats"].each do |benchmark_name, stats_array|
            next if stats_array.nil?
            stats_array.compact!
            next if stats_array.empty?
            benchmark_name = benchmark_name.sub(/.rb$/, "") if normalize_bench_names
            @yjit_stats[config_name][benchmark_name] ||= []
            @yjit_stats[config_name][benchmark_name].concat(stats_array)
        end

        @benchmark_metadata[config_name] ||= {}
        benchmark_results["benchmark_metadata"].each do |benchmark_name, metadata_for_benchmark|
            benchmark_name = benchmark_name.sub(/.rb$/, "") if normalize_bench_names
            @benchmark_metadata[config_name][benchmark_name] ||= metadata_for_benchmark
            if @benchmark_metadata[config_name][benchmark_name] != metadata_for_benchmark
                # We don't print this warning only once because it's really bad, and because we'd like to show it for all
                # relevant problem benchmarks. But mostly because it's really bad: don't combine benchmark runs with
                # different settings into one result set.
                $stderr.puts "WARNING: multiple benchmark runs of #{benchmark_name} in #{config_name} have different benchmark metadata!"
            end
        end

        @ruby_metadata[config_name] ||= benchmark_results["ruby_metadata"]
        if @ruby_metadata[config_name] != benchmark_results["ruby_metadata"] && !@printed_ruby_metadata_warning
            print "Ruby metadata is meant to *only* include information that should always be\n" +
              "  the same for the same Ruby executable. Please verify that you have not added\n" +
              "  inappropriate Ruby metadata or accidentally used the same name for two\n" +
              "  different Ruby executables. (Additional mismatches in this result set won't show warnings.)\n"
            puts "Metadata 1: #{@ruby_metadata[config_name].inspect}"
            puts "Metadata 2: #{benchmark_results["ruby_metadata"].inspect}"
            @printed_ruby_metadata_warning = true
        end

        @peak_mem[config_name] ||= {}
        benchmark_results["peak_mem_bytes"].each do |benchmark_name, mem_bytes|
            benchmark_name = benchmark_name.sub(/.rb$/, "") if normalize_bench_names
            @peak_mem[config_name][benchmark_name] ||= []
            @peak_mem[config_name][benchmark_name].concat(mem_bytes)
        end
    end

    # This returns a hash-of-arrays by configuration name
    # containing benchmark results (times) per
    # benchmark for the specified config.
    #
    # If in_runs is specified, the array will contain
    # arrays (runs) of samples. Otherwise all samples
    # from all runs will be combined.
    def times_for_config_by_benchmark(config, in_runs: false)
        raise("No results for configuration: #{config.inspect}!") if !@times.has_key?(config) || @times[config].empty?
        return @times[config] if in_runs
        data = {}
        @times[config].each do |benchmark_name, runs|
            data[benchmark_name] = runs.inject([]) { |arr, piece| arr.concat(piece) }
        end
        data
    end

    # This returns a hash-of-arrays by configuration name
    # containing warmup results (times) per
    # benchmark for the specified config.
    #
    # If in_runs is specified, the array will contain
    # arrays (runs) of samples. Otherwise all samples
    # from all runs will be combined.
    def warmups_for_config_by_benchmark(config, in_runs: false)
        return @warmups[config] if in_runs
        data = {}
        @warmups[config].each do |benchmark_name, runs|
            data[benchmark_name] = runs.inject([]) { |arr, piece| arr.concat(piece) }
        end
        data
    end

    # This returns a hash-of-arrays by config name
    # containing YJIT statistics, if gathered, per
    # benchmark run for the specified config. For configs
    # that don't collect YJIT statistics, the array
    # will be empty.
    #
    # If in_runs is specified, the array will contain
    # arrays (runs) of samples. Otherwise all samples
    # from all runs will be combined.
    def yjit_stats_for_config_by_benchmark(config, in_runs: false)
        return @yjit_stats[config] if in_runs
        data = {}
        @yjit_stats[config].each do |benchmark_name, runs|
            data[benchmark_name] = runs.inject([]) { |arr, piece| arr.concat(piece) }
        end
        data
    end

    def peak_mem_bytes_for_config_by_benchmark(config)
        @peak_mem[config]
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

    # Sometimes you just want all the yjit_stats fields added up.
    #
    # This should return a hash-of-hashes where the top level key
    # key is the benchmark name and each hash value is the combined stats
    # for a single benchmark across whatever number of runs is present.
    #
    # This may not work as expected if you have full YJIT stats only
    # sometimes for a given config - which normally should never be
    # the case.
    def combined_yjit_stats_for_config_by_benchmark(config)
        data = {}
        @yjit_stats[config].each do |benchmark_name, runs|
            stats = {}
            runs.map(&:flatten).map(&:first).each do |run|
                raise "Internal error! #{run.class.name} is not a hash!" unless run.is_a?(Hash)

                stats["all_stats"] = run["all_stats"] if run["all_stats"]
                (run.keys - ["all_stats"]).each do |key|
                    stats[key] ||= 0
                    stats[key] += run[key]
                end
            end
            data[benchmark_name] = stats
        end
        data
    end

    # Summarize the data by config. If it's a YJIT config with full stats, get the highlights of the exit report too.
    SUMMARY_STATS = [
        "inline_code_size",
        "outlined_code_size",
        "exec_instruction",
        "vm_insns_count",
        "compiled_iseq_count",
        "leave_interp_return",
        "compiled_block_count",
        "invalidation_count",
        "constant_state_bumps",
    ]
    def summary_by_config_and_benchmark
        summary = {}
        available_configs.each do |config|
            summary[config] = {}

            times_by_bench = times_for_config_by_benchmark(config)
            times_by_bench.each do |bench, results|
                summary[config][bench] = {
                    "mean" => mean(results),
                    "stddev" => stddev(results),
                    "rel_stddev" => rel_stddev(results),
                }
            end

            all_stats = combined_yjit_stats_for_config_by_benchmark(config)
            all_stats.each do |bench, stats|
                summary[config][bench]["yjit_stats"] = stats.slice(*SUMMARY_STATS)

                # Do we have full YJIT stats? If so, let's add the relevant summary bits
                if stats["all_stats"]
                    out_stats = summary[config][bench]["yjit_stats"]
                    out_stats["side_exits"] = stats.inject(0) { |total, (k, v)| total + (k.start_with?("exit_") ? v : 0) }
                    out_stats["total_exits"] = out_stats["side_exits"] + out_stats["leave_interp_return"]
                    out_stats["retired_in_yjit"] = out_stats["exec_instruction"] - out_stats["side_exits"]
                    out_stats["avg_len_in_yjit"] = out_stats["retired_in_yjit"].to_f / out_stats["total_exits"]
                    out_stats["total_insns_count"] = out_stats["retired_in_yjit"] + out_stats["vm_insns_count"]
                    out_stats["yjit_ratio_pct"] = 100.0 * out_stats["retired_in_yjit"] / out_stats["total_insns_count"]
                end
            end
        end
        summary
    end

    # What Ruby configurations, if any, have full YJIT statistics available?
    def configs_containing_full_yjit_stats
        @yjit_stats.keys.select do |config_name|
            stats = @yjit_stats[config_name]

            # Every benchmark gets a key/value pair in stats, and every
            # value is an array of arrays -- each run gets an array, and
            # each measurement in the run gets an array.

            # Even "non-stats" YJITs now have statistics, but not "full" statistics

            # If stats is nil or empty, this isn't a full-yjit-stats config
            if stats.nil? || stats.empty?
                false
            else
                # For each benchmark, grab its array of runs
                vals = stats.values

                vals.all? { |run_values| }
            end

            # Stats is a hash of the form { "30_ifelse" => [ { "all_stats" => true, "inline_code_size" => 5572282, ...}, {...} ], "30k_methods" => [ {}, {} ]}
            # We want to make sure every run has an all_stats hash key.
            !stats.nil? &&
                !stats.empty? &&
                !stats.values.all? { |val| val.nil? || val[0].nil? || val[0][0].nil? || val[0][0]["all_stats"].nil? }
        end
    end
end

module YJITMetrics
    # Default settings for Benchmark CI.
    # This is used by benchmark_and_update.rb for CI reporting directly.
    # It's also used by the VariableWarmupReport when selecting appropriate
    # benchmarking settings.
    DEFAULT_CI_SETTINGS = {
        # Config names and config-specific settings
        "configs" => {
            # Each config controls warmup individually. But the number of real iterations needs
            # to match across all configs, so it's not set per-config.
            "yjit_stats" => {
                max_warmup_itrs: 20,
                warmup_type: :simple,
            },
            "prod_ruby_no_jit" => {
                max_warmup_itrs: 5,
                warmup_type: :simple,
            },
            "prod_ruby_with_yjit" => {
                max_warmup_itrs: 20,
                # "Simple" warmup means after X iterations, we know everything relevant is fully warmed up.
                # We're not currently using the warmup_type, but we may in the future.
                warmup_type: :simple,
            },
            "ruby_30_with_mjit" => {
                max_warmup_itrs: 20,
                # "Delayed" warmup means it may take arbitrary extra time before compilation, but it's a one-shot compile
                warmup_type: :delayed,
            },
            "prod_ruby_with_mjit" => {
                max_warmup_itrs: 75,
                max_warmup_time: 300, # in seconds
                # "Complex" warmup means there can be multiple levels of warmup. We don't know how long it takes, and we never really know we're done.
                warmup_type: :complex,
            },
        },
        # Basic settings, outside of all specific configs
        "min_bench_itrs" => 15,
        "min_bench_time" => 20,
        "min_warmup_itrs" => 5,
        "max_warmup_itrs" => 75,
        "max_itr_time" => 300 * 60,  # GitHub Actions cuts off at 360 minutes, so allow 300 expected minutes of non-overhead iteration time
    }
end

# Shared utility methods for reports that use a single "blob" of results
class YJITMetrics::Report
    include YJITMetrics::Stats

    def self.subclasses
        @subclasses ||= []
        @subclasses
    end

    def self.inherited(subclass)
        YJITMetrics::Report.subclasses.push(subclass)
    end

    def self.report_name_hash
        out = {}

        @subclasses.select { |s| s.respond_to?(:report_name) }.each do |subclass|
            name = subclass.report_name
            raise "Duplicated report name: #{name.inspect}!" if out[name]
            out[name] = subclass
        end

        out
    end

    def initialize(config_names, results, benchmarks: [])
        raise "No Rubies specified!" if config_names.empty?

        bad_configs = config_names - results.available_configs
        raise "Unknown configurations in report: #{bad_configs.inspect}!" unless bad_configs.empty?

        @config_names = config_names
        @only_benchmarks = benchmarks
        @result_set = results
    end

    # Child classes can accept params in this way. By default it's a no-op.
    def set_extra_info(info)
        @extra_info = info
    end

    # Do we specifically recognize this extra field? Nope. Child classes can override.
    def accepts_field(name)
        false
    end

    def filter_benchmark_names(names)
        return names if @only_benchmarks.empty?
        names.select { |bench_name| @only_benchmarks.any? { |bench_spec| bench_name.start_with?(bench_spec) } }
    end

    # Take column headings, formats for the percent operator and data, and arrange it
    # into a simple ASCII table returned as a string.
    def format_as_table(headings, col_formats, data, separator_character: "-", column_spacer: "  ")
        out = ""

        unless data && data[0] && col_formats && col_formats[0] && headings && headings[0]
            $stderr.puts "Error in format_as_table..."
            $stderr.puts "Headings: #{headings.inspect}"
            $stderr.puts "Col formats: #{col_formats.inspect}"
            $stderr.puts "Data: #{data.inspect}"
            raise "Invalid data sent to format_as_table"
        end

        num_cols = data[0].length
        raise "Mismatch between headings and first data row for number of columns!" unless headings.length == num_cols
        raise "Data has variable number of columns!" unless data.all? { |row| row.length == num_cols }
        raise "Column formats have wrong number of entries!" unless col_formats.length == num_cols

        formatted_data = data.map.with_index do |row, idx|
            col_formats.zip(row).map { |fmt, item| item ? fmt % item : "" }
        end

        col_widths = (0...num_cols).map { |col_num| (formatted_data.map { |row| row[col_num].length } + [ headings[col_num].length ]).max }

        out.concat(headings.map.with_index { |h, idx| "%#{col_widths[idx]}s" % h }.join(column_spacer), "\n")

        separator = col_widths.map { |width| separator_character * width }.join(column_spacer)
        out.concat(separator, "\n")

        formatted_data.each do |row|
            out.concat (row.map.with_index { |item, idx| " " * (col_widths[idx] - item.size) + item }).join(column_spacer), "\n"
        end

        out.concat("\n", separator, "\n")
    rescue
        $stderr.puts "Error when trying to format table: #{headings.inspect} / #{col_formats.inspect} / #{data[0].inspect}"
        raise
    end

    def write_to_csv(filename, data)
        CSV.open(filename, "wb") do |csv|
            data.each { |row| csv << row }
        end
    end

end

# Class for reports that use a longer series of times, each with its own report/data.
class YJITMetrics::TimelineReport
    include YJITMetrics::Stats

    def self.subclasses
        @subclasses ||= []
        @subclasses
    end

    def self.inherited(subclass)
        YJITMetrics::TimelineReport.subclasses.push(subclass)
    end

    def self.report_name_hash
        out = {}

        @subclasses.select { |s| s.respond_to?(:report_name) }.each do |subclass|
            name = subclass.report_name
            raise "Duplicated report name: #{name.inspect}!" if out[name]
            out[name] = subclass
        end

        out
    end

    def initialize(context)
        @context = context
    end

end
