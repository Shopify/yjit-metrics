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
        @with_mjit_config = exactly_one_config_with_name(@config_names, "prod_ruby_with_mjit", "with-MJIT", none_okay: true)
        @no_jit_config    = exactly_one_config_with_name(@config_names, "no_jit", "no-JIT")

        # Order matters here - we push No-JIT, then MJIT(s), then YJIT.
        @configs_with_human_names = [
            ["No JIT", @no_jit_config],
        ]
        @configs_with_human_names.push(["MJIT", @with_mjit_config]) if @with_mjit_config
        @configs_with_human_names.push(["YJIT", @with_yjit_config])

        # Grab relevant data from the ResultSet
        @warmups_by_config = {}
        @times_by_config = {}
        @iters_by_config = {}
        @ruby_metadata_by_config = {}
        @bench_metadata_by_config = {}

        YJITMetrics::PLATFORMS.each do |platform|
            next if @result_set[platform].empty?

            platform_configs = @result_set[platform].config_names
            @configs_with_human_names.map { |name, config| config }.each do |config|
                next unless platform_configs.include?(config)

                @warmups_by_platform_and_config[platform][config] = @result_set[platform].warmups_for_config_by_benchmark(config, in_runs: true)
                @times_by_platform_and_config[platform][config] = @result_set[platform].times_for_config_by_benchmark(config, in_runs: true)

                @warmups_by_platform_and_config[platform][config].keys.each do |bench_name|
                    @iters_by_platform_and_config[platform][config] ||= {}
                    # For each run, add its warmups to its timed iterations in a single array.
                    runs = @warmups_by_platform_and_config[platform][config][bench_name].zip(@times_by_platform_and_config[platform][config][bench_name]).map { |a, b| a + b }
                    @iters_by_platform_and_config[platform][config][bench_name] = runs
                end

                @ruby_metadata_by_platform_and_config[platform][config] = @result_set[platform].metadata_for_config(config)
                @bench_metadata_by_platform_and_config[platform][config] = @result_set[platform].benchmark_metadata_for_config_by_benchmark(config)
            end
        end

        all_bench_names = @times_by_platform_and_config.values.map { |configs_hash| configs_hash[@with_yjit_config].keys }.sum([]).uniq
        @benchmark_names = filter_benchmark_names(all_bench_names)
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
        # Initial "blank" settings for each relevant config and benchmark
        looked_up_configs = @configs_with_human_names.map { |_, config| config }.sort
        default_configs = default_settings["configs"].keys.sort
        all_configs = (looked_up_configs + default_configs).uniq.sort

        warmup_settings = all_configs.to_h do |config|
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
            # Find the fastest mean iteration across all platforms and configs.
            fastest_itr_time_ms = YJITMetrics::PLATFORMS.map do |platform|
                summary = @result_set[platform].summary_by_config_and_benchmark
                default_configs.map { |config| summary.dig(config, bench_name, "mean") }.compact.min
            end.compact.min || 10_000_000.0

            min_itrs_needed = (default_settings["min_bench_time"] * 1000.0 / fastest_itr_time_ms).to_i
            min_itrs_needed = [ min_itrs_needed, default_settings["min_bench_itrs"] ].max

            YJITMetrics::PLATFORMS.each do |platform|
                summary = @result_set[platform].summary_by_config_and_benchmark

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
        end

        # How much total time have we allocated to running benchmarks?
        est_time = default_configs.map do |config|
            # Pretend yjit_stats iterations will take as long as prod YJIT, though it's really longer
            config = @with_yjit_config if config == "yjit_stats"

            warmup_settings[config].values.map { |s| s[:estimated_time] || 0.0 }.sum
        end.sum
        warmup_settings["estimated_time"] = est_time

        # Do we need to reduce the time taken?
        if est_time > default_settings["max_itr_time"]
            puts "Maximum allowed time: #{default_settings["max_itr_time"].inspect}sec"
            puts "Estimated run time: #{est_time.inspect}sec"
            raise "This is where logic to do something statistical and clever would go!"
        end

        warmup_settings
    end

    def write_file(filename)
        settings = iterations_for_configs_and_benchmarks(@default_yjit_bench_settings)

        puts "Writing file: #{filename}.warmup_settings.json"
        File.open(filename + ".warmup_settings.json", "w") { |f| f.puts JSON.pretty_generate settings }
    end
end
