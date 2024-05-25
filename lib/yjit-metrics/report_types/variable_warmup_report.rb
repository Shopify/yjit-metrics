# And here is where we get into... cleverness :-/

# This report intends to look over the most recent results for a specific benchmark and Ruby configuration
# and determine how much warmup is really required or useful. Where possible we should be a bit conservative
# and run additional warmups, and we should check to see if we might be inadequately warming up a particular
# combination.

# We don't want to let warmup or number of iterations get so high that we run over the GitHub Actions
# maximum job duration.

class YJITMetrics::VariableWarmupReport < YJITMetrics::Report
    def self.report_name
        "variable_warmup"
    end

    def self.report_extensions
        "warmup_settings.json"
    end

    # The internal state of these is huge - reduce the size of debug output when calling a bad
    # method...
    def inspect
        "VariableWarmupReport<#{self.object_id}>"
    end

    CORRELATION_THRESHOLD = 0.1

    def look_up_data_by_ruby
        # Order matters here - we push No-JIT, then MJIT(s), then YJIT. For each one we sort by platform name.
        # It matters because we want the output reports to be stable with no churn in Git.
        bench_configs = YJITMetrics::DEFAULT_YJIT_BENCH_CI_SETTINGS["configs"]
        configs = @result_set.config_names
        config_order = []
        config_order += configs.select { |c| c["prev_ruby_no_jit"] }.sort # optional
        config_order += configs.select { |c| c["prod_ruby_no_jit"] }.sort
        config_order += configs.select { |c| c["prod_ruby_with_mjit"] }.sort # MJIT is optional, may be empty
        config_order += configs.select { |c| c["prev_ruby_yjit"] }.sort # optional
        config_order += configs.select { |c| c["prod_ruby_with_yjit"] }.sort
        # TODO: Something about this calculation is off, when we include the
        # data from the stats config it overestimates the time spent.
        # config_order += configs.select { |c| c["yjit_stats"] }.sort # Stats configs *also* take time to run
        @configs_with_human_names = @result_set.configs_with_human_names(config_order)

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

        all_bench_names = @times_by_config[config_order[-1]].keys
        @benchmark_names = filter_benchmark_names(all_bench_names)

        @times_by_config.each do |config_name, config_results|
            if config_results.nil? || config_results.empty?
                raise("No results for configuration #{config_name.inspect} in #{self.class}!")
            end
        end
    end

    def initialize(config_names, results,
        default_yjit_bench_settings: ::YJITMetrics::DEFAULT_YJIT_BENCH_CI_SETTINGS, benchmarks: [])

        # Set up the parent class, look up relevant data
        super(config_names, results, benchmarks: benchmarks)

        @default_yjit_bench_settings = default_yjit_bench_settings

        look_up_data_by_ruby
    end

    # Figure out how many iterations, warmup and non-, for each Ruby config and benchmark
    def iterations_for_configs_and_benchmarks(default_settings)
        # Note: default_configs are config *roots*, not full configurations
        default_configs = default_settings["configs"].keys.sort

        warmup_settings = default_configs.to_h do |config|
            [ config, @benchmark_names.to_h do |bench_name|
                    [ bench_name,
                        {
                            # Conservative defaults - sometimes these are for Ruby configs we know nothing about,
                            # because they're not present in recent-at-the-time benchmark data.
                            warmup_itrs: default_settings["min_warmup_itrs"],
                            min_bench_itrs: default_settings["min_bench_itrs"],
                            min_bench_time: 0,
                        }
                    ]
                end
            ]
        end

        @benchmark_names.each do |bench_name|
            idx = @benchmark_names.index(bench_name)

            # Number of iterations is chosen per-benchmark, but stays the same across all configs.
            # Find the fastest mean iteration across all configs.
            summary = @result_set.summary_by_config_and_benchmark
            fastest_itr_time_ms = default_configs.map do |config|
                summary.dig(config, bench_name, "mean")
            end.compact.min || 10_000_000.0

            min_itrs_needed = (default_settings["min_bench_time"] * 1000.0 / fastest_itr_time_ms).to_i
            min_itrs_needed = [ min_itrs_needed, default_settings["min_bench_itrs"] ].max

            default_configs.each do |config|
                config_settings = default_settings["configs"][config]

                itr_time_ms = summary.dig(config, bench_name, "mean")
                ws = warmup_settings[config][bench_name]
                raise "No warmup settings found for #{config.inspect}/#{bench_name.inspect}!" if ws.nil?

                ws[:min_bench_itrs] = min_itrs_needed

                # Do we have an estimate of how long this takes per iteration? If so, include it.
                ws[:itr_time_ms] = ("%.2f" % [ws[:itr_time_ms], itr_time_ms].compact.max) unless itr_time_ms.nil?

                # Warmup is chosen per-config to reduce unneeded warmup for low-warmup configs
                ws[:warmup_itrs] = config_settings[:max_warmup_itrs]
                if config_settings[:max_warmup_time] && itr_time_ms
                    # itr_time_ms is in milliseconds, while max_warmup_time is in seconds
                    max_allowed_warmup = config_settings[:max_warmup_time] * 1000.0 / itr_time_ms
                    # Choose the tighter of the two warmup limits
                    ws[:warmup_itrs] = max_allowed_warmup if ws[:warmup_itrs] > max_allowed_warmup
                end

                if itr_time_ms
                    itrs = ws[:warmup_itrs] + ws[:min_bench_itrs]
                    est_time_ms = itrs * (itr_time_ms || 0.0)
                    ws[:estimated_time] = ((est_time_ms + 999.0) / 1000).to_i  # Round up for elapsed time
                else
                    ws[:estimated_time] = 0 unless ws[:estimated_time]
                end
                #puts "Est time #{config.inspect} #{bench_name.inspect}: #{itrs} * #{"%.1f" % (itr_time_ms || 0.0)}ms = #{ws[:estimated_time].inspect}sec"
            end
        end

        platform_configs = {}
        @configs_with_human_names.values.each do |config|
            config_platform = YJITMetrics::PLATFORMS.detect { |platform| config.start_with?(platform) }
            platform_configs[config_platform] ||= []
            platform_configs[config_platform] << config
        end

        # How much total time have we allocated to running benchmarks per platform?
        platform_configs.each do |platform, configs|
            est_time = configs.map do |config|
                warmup_settings[config].values.map { |s| s[:estimated_time] || 0.0 }.sum
            end.sum
            warmup_settings["#{platform}_estimated_time"] = est_time

            # Do we need to reduce the time taken?
            if est_time > default_settings["max_itr_time"]
                puts "Maximum allowed time: #{default_settings["max_itr_time"].inspect}sec"
                puts "Estimated run time on #{platform}: #{est_time.inspect}sec"
                raise "This is where logic to do something statistical and clever would go!"
            end
        end

        warmup_settings
    end

    def write_file(filename)
        settings = iterations_for_configs_and_benchmarks(@default_yjit_bench_settings)

        puts "Writing file: #{filename}.warmup_settings.json"
        File.open(filename + ".warmup_settings.json", "w") { |f| f.puts JSON.pretty_generate settings }
    end
end
