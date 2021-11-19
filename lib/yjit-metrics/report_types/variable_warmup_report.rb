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

    # The input series is a set of measured iteration times.
    # We'll convert that to coordinates and take their correlation.
    def series_benchmark_correlation(series)
        # Treat each iteration as starting immediately after the previous one.
        # That way long iterations start a longer time after the previous sample.
        # That's useful for catching correlation due to (e.g.) MJIT's compiler
        # running in the background, and the more it slows the current iteration,
        # the more time it has had to improve the code.
        #
        # It would also be possible to just use a 1...N series for y, but I
        # think that would be less accurate.

        x = []
        y = []
        running_total = 0.0
        series.each do |sample|
            x.push sample
            y.push running_total
            running_total += sample
        end

        pearson_correlation(x, y)
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

                this_config_mean = mean(this_config_times)
                this_config_stddev = stddev(this_config_times)
                this_config_rel_stddev = rel_stddev(this_config_times)

                # Now we'll look at the correlations. Do we get a stronger correlation
                # for the whole set of iters than for the second half? If so that's
                # a bad sign, since both should be uncorrelated, within measurement error.
                second_half_times = this_config_times[(this_config_times.size / 2)..-1]
                corr = series_benchmark_correlation(this_config_times)
                second_half_corr = series_benchmark_correlation(second_half_times)

                @stability_by_config[config].push({
                    mean: this_config_mean,
                    stddev: this_config_stddev,
                    rel_stddev: this_config_rel_stddev,
                    correlation: corr,
                    second_half_correlation: second_half_corr,
                })
            end
        end
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the parent class, look up relevant data
        super

        look_up_data_by_ruby
        calc_stability_by_config


    end

    def write_file(filename)
    end
end
