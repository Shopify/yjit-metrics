# And here is where we get into... cleverness :-/

# This report intends to look over the most recent results for a specific benchmark and Ruby configuration
# and determine how much warmup is really required or useful. Where possible we should be a bit conservative
# and run additional warmups, and we should check to see if we might be inadequately warming up a particular
# combination.

# The reason we care is that we're now running quite long warmups for MJIT in 3.1 prerelease. Just making
# every benchmark take the same number of warmup iterations is no longer cutting it - that wastes vast
# amounts of time on more warmup than is needed for some Ruby configs while shortchanging others.

# By checking whether we're warming up, we can notice problems that we'd previously ignore (resource leaks,
# inadequate warmup) while avoiding massively-long warmups in places we don't need them.

# It's important that we don't miss "delayed warmup" to the extent possible. For instance, MJIT 3.1 may
# have rock-solid performance at first *until the compiler kicks in*. And so cutting warmups too short
# risks not seeing that problem. We need to make sure nothing *too* short is chosen, and that we have
# a few extra iterations to make sure drift over time results in correcting the warmups/iters, not
# continuing to use outdated measurements.

# This is intended to be significantly more intelligent than our initial "just do X iterations and take
# up to Y time" logic. It is still woefully inadequate for genuinely complicated implementations like
# TruffleRuby. The gold standard for such things is to have some view into the implementation's internal
# state so that we can let it warm up to its own satisfaction. We're still waiting for details of the
# TruffleRuby Thermometer interface, though.

# Mostly we're going to look for correlation (https://en.wikipedia.org/wiki/Pearson_correlation_coefficient)
# between sample and time - a strong positive or negative correlation with time is a bad thing, and
# suggests results are getting better or worse over time. What we want post-warmup is as little time
# correlation as possible.

class YJITMetrics::VariableWarmupReport < YJITMetrics::Report
    def self.report_name
        "variable_warmup"
    end

    CORRELATION_THRESHOLD = 0.1

    def exactly_one_config_with_name(configs, substring, description, none_okay: false)
        matching_configs = configs.select { |name| name.include?(substring) }
        raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
        raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty? && !none_okay
        matching_configs[0]
    end

    # We could probably make this a lot more flexible and just evaluate *every* config and benchmark.
    def look_up_data_by_ruby
        @with_yjit_config = exactly_one_config_with_name(@config_names, "with_yjit", "with-YJIT")
        @with_mjit30_config = exactly_one_config_with_name(@config_names, "ruby_30_with_mjit", "with-MJIT3.0", none_okay: true)
        @with_mjit31_config = exactly_one_config_with_name(@config_names, "prod_ruby_with_mjit", "with-MJIT3.1", none_okay: true)
        @no_jit_config    = exactly_one_config_with_name(@config_names, "no_jit", "no-JIT")

        unless @with_mjit30_config || @with_mjit31_config
            raise "We couldn't find an MJIT 3.0 or 3.1 config!"
        end

        # Order matters here - we push No-JIT, then MJIT(s), then YJIT.
        @configs_with_human_names = [
            ["No JIT", @no_jit_config],
        ]
        @configs_with_human_names.push(["MJIT3.0", @with_mjit30_config]) if @with_mjit30_config
        @configs_with_human_names.push(["MJIT3.1", @with_mjit31_config]) if @with_mjit31_config
        @configs_with_human_names.push(["YJIT", @with_yjit_config])

        # Grab relevant data from the ResultSet
        @warmups_by_config = {}
        @times_by_config = {}
        @iters_by_config = {}
        @ruby_metadata_by_config = {}
        @bench_metadata_by_config = {}
        @configs_with_human_names.map { |name, config| config }.each do |config|
            @warmups_by_config[config] = @result_set.warmups_for_config_by_benchmark(config, in_runs: true)
            @times_by_config[config] = @result_set.times_for_config_by_benchmark(config, in_runs: true)

            @warmups_by_config[config].keys.each do |bench_name|
                @iters_by_config[config] ||= {}
                # For each run, add its warmups to its timed iterations in a single array.
                runs = @warmups_by_config[config][bench_name].zip(@times_by_config[config][bench_name]).map { |a, b| a + b }
                @iters_by_config[config][bench_name] = runs
            end

            @ruby_metadata_by_config[config] = @result_set.metadata_for_config(config)
            @bench_metadata_by_config[config] = @result_set.benchmark_metadata_for_config_by_benchmark(config)
        end

        @benchmark_names = filter_benchmark_names(@times_by_config[@with_yjit_config].keys)

        @times_by_config.each do |config_name, config_results|
            if config_results.nil? || config_results.empty?
                raise("No results for configuration #{config_name.inspect} in #{self.class}!")
            end
        end
    end

    # Treat each iteration as starting immediately after the previous one.
    # That way long iterations start a longer time after the previous sample.
    # That's useful for catching correlation due to (e.g.) MJIT's compiler
    # running in the background, and the more it slows the current iteration,
    # the more time it has had to improve the code.
    #
    # It would also be possible to just use a 1...N series for y, but I
    # think that would be less accurate.
    def benchmark_series_to_xy_series(series)
        x = []
        y = []
        running_total = 0.0
        series.each do |sample|
            x.push running_total
            y.push sample
            running_total += sample
        end

        [x, y]
    end

    # The input series is a set of measured iteration times.
    # We'll convert that to coordinates and take their correlation.
    def series_benchmark_correlation(series)
        x, y = benchmark_series_to_xy_series(series)

        #pearson_correlation(x, y)
        least_squares_slope_intercept_and_correlation(x, y)[2]
    end

    def series_benchmark_least_squares(series)
        x, y = benchmark_series_to_xy_series(series)

        least_squares_slope_intercept_and_correlation(x, y)
    end

    def series_benchmark_simple_slope(series)
        x, y = benchmark_series_to_xy_series(series)

        simple_regression_slope(x, y)
    end

    def calc_stability_by_config
        @total_time_by_config = {}
        @stability_by_config = {}

        @configs_with_human_names.map { |name, config| config }.each do |config|
            @stability_by_config[config] = []
            @total_time_by_config[config] = 0.0
        end

        @benchmark_names.each do |benchmark_name|
            @configs_with_human_names.each do |name, config|
                # concat all runs, non-warmup iters only
                times = @times_by_config[config][benchmark_name]
                raise "Not handling variable-warmup reporting for multiple runs yet!" if times && times.size > 1

                unless times
                    # When is this nil? When a benchmark didn't happen for this config and benchmark.
                    @stability_by_config[config].push nil
                    next
                end

                this_config_times = times.inject([], &:+)
                @total_time_by_config[config] += this_config_times.sum

                this_config_warmup_times = @warmups_by_config[config][benchmark_name].flatten(1)

                this_config_mean = mean(this_config_times)
                this_config_stddev = stddev(this_config_times)
                this_config_rel_stddev = rel_stddev(this_config_times)

                # Now we'll look at the correlations. Do we get a significantly stronger
                # correlation for the whole set of iters than for the second half? If so that's
                # a bad sign. Both should be uncorrelated within measurement error.
                # It's during warmup that you'd expect significant slope.
                second_half_times = this_config_times[(this_config_times.size / 2)..-1]
                second_half_corr = series_benchmark_correlation(second_half_times)

                slope = series_benchmark_simple_slope(this_config_times)

                ls = series_benchmark_least_squares(this_config_times)
                warmup_ls = series_benchmark_least_squares(this_config_warmup_times)

                @stability_by_config[config].push({
                    times: this_config_times,
                    warmups: this_config_warmup_times,
                    size: this_config_times.size,
                    mean: this_config_mean,
                    stddev: this_config_stddev,
                    rel_stddev: this_config_rel_stddev,
                    correlation: ls[2],
                    warmup_slope: warmup_ls[0],
                    warmup_correlation: warmup_ls[2],
                    second_half_correlation: second_half_corr,
                    slope: ls[0],
                    simple_regression_slope: slope,
                    least_squares: ls,
                })
            end
        end
    end

    def initialize(config_names, results, default_settings: ::YJITMetrics::DEFAULT_CI_SETTINGS, benchmarks: [])
        # Set up the parent class, look up relevant data
        super(config_names, results, benchmarks: benchmarks)

        @default_settings = default_settings

        look_up_data_by_ruby
        calc_stability_by_config

        calc_statistics_of_interest
    end

    # Look through the calculated stability and statistics information.
    # Do we see anything odd or concerning? This will go in a separate report
    # to be looked through manually or maybe eventually alerted on.
    def calc_statistics_of_interest
        @stats_of_interest = {}
        looked_up_configs = @configs_with_human_names.map { |_, config| config }.sort

        looked_up_configs.each do |config|
            @stats_of_interest[config] = {}
            @benchmark_names.each.with_index do |bench_name, idx|
                @stats_of_interest[config][bench_name] = {
                    warnings: [],
                }
            end
        end

        # When using No-JIT, you can't get JIT resource leaks or noise
        # from warmups. Do we see something that seems to be unreasonably noisy,
        # or continuously slowing down? If so, tag it.
        #
        # Any bug with the No-JIT config is a bug with the benchmark, not a
        # JIT implementation.
        @stability_by_config[@no_jit_config].each.with_index do |stats, idx|
            bench_name = @benchmark_names[idx]

            # Ordinarily you'd expect a least-squares line fit to find so-so correlation
            # with a horizontal line. If we get *good* correlation with a positive-slope line,
            # with a slope around the size of the stddev, that's a sign of trouble. It means the
            # benchmark gets significantly slower as it runs.

            # Good correlation with a negative-slope line suggests inadequate warmup - the benchmark is
            # still getting faster during the "real" iterations. Also not great.

            # Low correlation is usually fine. If you measure a bunch of points and they look like a
            # cloud of noise without any particular slope, that probably means you're getting normal,
            # expected measurement noise. Similarly, flat slope is great. Flat slope usually means we're
            # getting enough warmup and no resource leaks.

            if stats[:slope].abs > 0.5 * stats[:stddev] #&& stats[:correlation] >= CORRELATION_THRESHOLD
                print "No-JIT #{bench_name}: slope: #{stats[:slope] / stats[:stddev]} StdDevs... correlation: #{"%.3f" % stats[:correlation]}, stddev: #{"%.3f" % stats[:stddev]}, simple-regression slope #{"%.4f" % stats[:simple_regression_slope]}\n"

                @stats_of_interest[@no_jit_config][bench_name][:warnings].push "Large slope in No-JIT benchmark data, slope #{"%2.f" % (stats[:slope] / stats[:stddev])} stddevs, correlation #{"%.2f" % stats[:correlation]}, sample size #{stats[:size]}!"
            end
        end


        @stability_by_config[]
    end

    # Figure out how many iterations, warmup and non-, for each Ruby config and benchmark
    def iterations_for_configs_and_benchmarks(default_settings)
        # Initial "blank" settings for each relevant config and benchmark
        looked_up_configs = @configs_with_human_names.map { |_, config| config }.sort
        default_configs = default_settings["configs"].keys.sort - ["unknown"]
        all_configs = (looked_up_configs + default_configs).uniq.sort

        warmup_settings = all_configs.to_h do |config|
            [ config, @benchmark_names.to_h do |bench_name|
                    [ bench_name,
                        {
                            # Conservative defaults - sometimes these are for Ruby configs we know nothing about,
                            # because they're not present in recent-at-the-time benchmark data.
                            warmup_itrs: default_settings[:min_warmup_itrs],
                            min_bench_itrs: default_settings[:min_bench_itrs],
                            min_bench_time: 0,
                        }
                    ]
                end
            ]
        end

        default_configs.each do |config|
            next if config == "yjit_stats" # This one gets handled specially
            settings = default_settings["configs"][config]

            @benchmark_names.each do |bench_name|
                idx = @benchmark_names.index(bench_name)
                stats = @stability_by_config[config] ? @stability_by_config[config][idx] : nil
                itr_time_ms = stats.nil? ? nil : stats[:mean]
                ws = warmup_settings[config][bench_name]

                # Do we have an estimate of how long this takes per iteration? If so, include it.
                ws[:itr_time_ms] = itr_time_ms unless itr_time_ms.nil?

                ws[:warmup_itrs] = settings[:max_warmup_itrs]
                if settings[:max_warmup_time] && itr_time_ms
                    # itr_time_ms is in milliseconds, while max_warmup_time is in seconds
                    max_allowed_itrs = settings[:max_warmup_time] * 1000.0 / itr_time_ms
                    # Choose the tighter of the two warmup limits
                    ws[:warmup_itrs] = max_allowed_itrs if ws[:warmup_itrs] > max_allowed_itrs
                end
                ws[:min_bench_itrs] = settings[:min_bench_itrs] || default_settings[:min_bench_itrs]

                itrs = ws[:warmup_itrs] + ws[:min_bench_itrs]
                est_time_ms = itrs * (itr_time_ms || 0.0)
                ws[:estimated_time] = ((est_time_ms + 999.0) / 1000).to_i  # Round up for elapsed time
                #puts "Est time #{config.inspect} #{bench_name.inspect}: #{itrs} * #{"%.1f" % (itr_time_ms || 0.0)}ms = #{ws[:estimated_time].inspect}sec"
            end
        end
        # We want the yjit_stats statistics to match the prod YJIT stats as much as feasible.
        warmup_settings["yjit_stats"] = warmup_settings[@with_yjit_config]

        # How much total time have we allocated to running benchmarks?
        est_time = default_configs.map do |config|
            # Pretend yjit_stats iterations will take as long as prod YJIT, though it's really longer
            config = @with_yjit_config if config == "yjit_stats"

            warmup_settings[config].values.map { |s| s[:estimated_time] }.sum
        end.sum
        warmup_settings["estimated_time"] = est_time

        # Do we need to reduce the time taken?
        if est_time > default_settings[:max_itr_time]
            puts "Maximum allowed time: #{default_settings[:max_itr_time].inspect}sec"
            puts "Estimated run time: #{est_time.inspect}sec"
            raise "This is where logic to do something statistical and clever would go!"
        end

        warmup_settings
    end

    def write_file(filename)
        settings = iterations_for_configs_and_benchmarks(@default_settings)

        puts "Writing file: #{filename}.warmup_settings.json"
        File.open(filename + ".warmup_settings.json", "w") { |f| f.puts JSON.pretty_generate settings }

        puts "Writing file: #{filename}.stats_of_interest.json"
        File.open(filename + ".stats_of_interest.json", "w") { |f| f.puts JSON.pretty_generate @stats_of_interest }
    end
end
