# frozen_string_literal: true

require "yaml"

require_relative "../../metrics_app/benchmarks"
require_relative "./yjit_stats_report"

# For details-at-a-specific-time reports, we'll want to find individual configs and make sure everything is
# present and accounted for. This is a "single" report in the sense that it's conceptually at a single
# time, even though it can be multiple runs and Rubies. What it is *not* is results over time as YJIT and
# the benchmarks change.
# This is a parent class for other reports and is not directly instantiated itself.
# As an example, SpeedDetailsMultiplatformReport will instantiate SpeedDetailsReport (a subclass of this class) once per platform.

module YJITMetrics
  class BloggableSingleReport < YJITStatsReport
    # Benchmarks sometimes go into multiple categories, based on the category field
    BENCHMARK_METADATA = YAML.load_file(MetricsApp::Benchmarks::DIR.join("benchmarks.yml")).map do |name, metadata|
      [name, metadata.transform_keys(&:to_sym)]
    end.to_h

    def headline_benchmarks
      @benchmark_names.select { |bench| BENCHMARK_METADATA[bench] && BENCHMARK_METADATA[bench][:category] == "headline" }
    end

    def micro_benchmarks
      @benchmark_names.select { |bench| BENCHMARK_METADATA[bench] && BENCHMARK_METADATA[bench][:category] == "micro" }
    end

    def benchmark_category_index(bench_name)
      return 0 if BENCHMARK_METADATA[bench_name] && BENCHMARK_METADATA[bench_name][:category] == "headline"
      return 2 if BENCHMARK_METADATA[bench_name] && BENCHMARK_METADATA[bench_name][:category] == "micro"
      return 1
    end

    class BenchNameLinkFormatter
      def %(bench_name)
        bench_desc = ( BENCHMARK_METADATA[bench_name] && BENCHMARK_METADATA[bench_name][:desc] ) || "(no description available)"
        suffix = BENCHMARK_METADATA[bench_name] && BENCHMARK_METADATA[bench_name][:single_file] ? ".rb" : "/benchmark.rb"
        bench_url = "https://github.com/ruby/ruby-bench/blob/main/benchmarks/#{bench_name}#{suffix}"

        %Q(<a href="#{bench_url}" title="#{bench_desc.gsub('"', '&quot;')}">#{bench_name}</a>)
      end
    end

    def bench_name_link_formatter
      BenchNameLinkFormatter.new
    end

    def exactly_one_config_with_name(configs, substring, description, none_okay: false)
      matching_configs = configs.select { |name| name.include?(substring) }

      raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
      raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty? && !none_okay

      matching_configs[0]
    end

    # YJIT and No-JIT are mandatory.
    def look_up_data_by_ruby(only_platforms: YJITMetrics::PLATFORMS, in_runs: false)
      only_platforms = [only_platforms].flatten
      # Filter config names by given platform(s)
      config_names = @config_names.select { |name| only_platforms.any? { |plat| name.include?(plat) } }
      raise "No data files for platform(s) #{only_platforms.inspect} in #{@config_names}!" if config_names.empty?

      @with_yjit_config = exactly_one_config_with_name(config_names, "prod_ruby_with_yjit", "with-YJIT")
      @prev_no_jit_config = exactly_one_config_with_name(config_names, "prev_ruby_no_jit", "prev-CRuby", none_okay: true)
      @prev_yjit_config = exactly_one_config_with_name(config_names, "prev_ruby_yjit", "prev-YJIT", none_okay: true)
      @no_jit_config    = exactly_one_config_with_name(config_names, "prod_ruby_no_jit", "no-JIT")
      @truffle_config   = exactly_one_config_with_name(config_names, "truffleruby", "Truffle", none_okay: true)

      # Prefer previous CRuby if present otherwise current CRuby.
      @baseline_config = @prev_no_jit_config || @no_jit_config

      # Order matters here - we push No-JIT, then YJIT and finally TruffleRuby when present
      @configs_with_human_names = [
        ["CRuby <version>", @prev_no_jit_config],
        ["CRuby <version>", @no_jit_config],
        ["YJIT <version>", @prev_yjit_config],
        ["YJIT <version>", @with_yjit_config],
        ["Truffle", @truffle_config],
      ].map do |(name, config)|
        [@result_set.insert_version_for_config(name, config), config] if config
      end.compact

      # Grab relevant data from the ResultSet
      @times_by_config = {}
      @warmups_by_config = {}
      @ruby_metadata_by_config = {}
      @bench_metadata_by_config = {}
      @peak_mem_by_config = {}
      @yjit_stats = {}
      @configs_with_human_names.map { |name, config| config }.each do |config|
        @times_by_config[config] = @result_set.times_for_config_by_benchmark(config, in_runs: in_runs)
        @warmups_by_config[config] = @result_set.warmups_for_config_by_benchmark(config, in_runs: in_runs)
        @ruby_metadata_by_config[config] = @result_set.metadata_for_config(config)
        @bench_metadata_by_config[config] = @result_set.benchmark_metadata_for_config_by_benchmark(config)
        @peak_mem_by_config[config] = @result_set.peak_mem_bytes_for_config_by_benchmark(config)
      end

      @yjit_stats = @result_set.yjit_stats_for_config_by_benchmark(@stats_config, in_runs: in_runs)
      @benchmark_names = filter_benchmark_names(@times_by_config[@with_yjit_config].keys)

      # Keep track of missing benchmarks so that in the loop we still check for
      # all so that warnings show everything missing from each config.
      # Then at the end we can remove the ones that aren't available for all.
      missing_benchmarks = []

      @times_by_config.each do |config_name, config_results|
        if config_results.nil? || config_results.empty?
          raise("No results for configuration #{config_name.inspect} in #{self.class}!")
        end

        no_result_benchmarks = @benchmark_names.select { |bench_name| config_results[bench_name].nil? || config_results[bench_name].empty? }
        unless no_result_benchmarks.empty?
          warn("No results in config #{config_name.inspect} for benchmark(s) #{no_result_benchmarks.inspect} in #{self.class}!")
          missing_benchmarks.concat(no_result_benchmarks)
        end
      end

      unless missing_benchmarks.empty?
        missing_benchmarks.uniq!
        warn("Removing benchmarks that are not present in all configs: #{missing_benchmarks.inspect}")
        @benchmark_names -= missing_benchmarks
      end

      no_stats_benchmarks = @benchmark_names.select { |bench_name| !@yjit_stats[bench_name] || !@yjit_stats[bench_name][0] || @yjit_stats[bench_name][0].empty? }
      unless no_stats_benchmarks.empty?
        raise "No YJIT stats found for benchmarks: #{no_stats_benchmarks.inspect}"
      end
    end

    def calc_speed_stats_by_config
      @mean_by_config = {}
      @rsd_pct_by_config = {}
      @speedup_by_config = {}
      @total_time_by_config = {}

      @configs_with_human_names.map { |name, config| config }.each do |config|
        @mean_by_config[config] = []
        @rsd_pct_by_config[config] = []
        @total_time_by_config[config] = 0.0
        @speedup_by_config[config] = []
      end

      @yjit_ratio = []

      @benchmark_names.each do |benchmark_name|
        @configs_with_human_names.each do |name, config|
          this_config_times = @times_by_config[config][benchmark_name]
          this_config_mean = mean_or_nil(this_config_times) # When nil? When a benchmark didn't happen for this config.
          @mean_by_config[config].push this_config_mean
          @total_time_by_config[config] += this_config_times.nil? ? 0.0 : sum(this_config_times)
          this_config_rel_stddev_pct = rel_stddev_pct_or_nil(this_config_times)
          @rsd_pct_by_config[config].push this_config_rel_stddev_pct
        end

        baseline_mean = @mean_by_config[@baseline_config][-1] # Last pushed -- the one for this benchmark
        baseline_rel_stddev_pct = @rsd_pct_by_config[@baseline_config][-1]
        baseline_rel_stddev = baseline_rel_stddev_pct / 100.0  # Get ratio, not percent
        @configs_with_human_names.each do |name, config|
          this_config_mean = @mean_by_config[config][-1]

          if this_config_mean.nil?
            @speedup_by_config[config].push [nil, nil]
          else
            this_config_rel_stddev_pct = @rsd_pct_by_config[config][-1]
            # Use (baseline / this) so that the bar goes up as the value (test duration) goes down.
            speed_ratio = baseline_mean / this_config_mean

            # For non-baseline we add the rsd for the config to the rsd
            # for the baseline to determine the full variance bounds.
            # For just the baseline we don't need to add anything.
            speed_rsd = if config == @baseline_config
              this_config_rel_stddev_pct
            else
              this_config_rel_stddev = this_config_rel_stddev_pct / 100.0 # Get ratio, not percent
              # Because we are dividing the baseline mean by this mean
              # to get a ratio we need to add the variance of each (the
              # baseline and this config) to determine the full error bounds.
              speed_rel_stddev = Math.sqrt(baseline_rel_stddev * baseline_rel_stddev + this_config_rel_stddev * this_config_rel_stddev)
              speed_rel_stddev * 100.0
            end

            @speedup_by_config[config].push [speed_ratio, speed_rsd]
          end

        end

        # A benchmark run may well return multiple sets of YJIT stats per benchmark name/type.
        # For these calculations we just add all relevant counters together.
        this_bench_stats = combined_stats_data_for_benchmarks([benchmark_name])

        total_exits = total_exit_count(this_bench_stats)
        retired_in_yjit = (this_bench_stats["exec_instruction"] || this_bench_stats["yjit_insns_count"]) - total_exits
        total_insns_count = retired_in_yjit + this_bench_stats["vm_insns_count"]
        yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count
        @yjit_ratio.push yjit_ratio_pct
      end
    end

    def calc_mem_stats_by_config
      @peak_mb_by_config = {}
      @peak_mb_relative_by_config = {}
      @configs_with_human_names.map { |name, config| config }.each do |config|
        @peak_mb_by_config[config] = []
        @peak_mb_relative_by_config[config] = []
      end
      @mem_overhead_factor_by_benchmark = []

      @inline_mem_used = []
      @outline_mem_used = []

      one_mib = 1024 * 1024.0 # As a float

      @benchmark_names.each.with_index do |benchmark_name, idx|
        @configs_with_human_names.each do |name, config|
          if @peak_mem_by_config[config][benchmark_name].nil?
            @peak_mb_by_config[config].push nil
            @peak_mb_relative_by_config[config].push [nil, nil]
          else
            this_config_bytes = mean(@peak_mem_by_config[config][benchmark_name])
            @peak_mb_by_config[config].push(this_config_bytes / one_mib)
          end
        end

        baseline_mean = @peak_mb_by_config[@baseline_config][-1]
        baseline_rsd = rel_stddev(@peak_mem_by_config[@baseline_config][benchmark_name])
        @configs_with_human_names.each do |name, config|
          if @peak_mem_by_config[config][benchmark_name].nil?
            @peak_mb_relative_by_config[config].push [nil]
          else
            values = @peak_mem_by_config[config][benchmark_name]
            this_config_mean_mb = mean(values) / one_mib
            # For baseline use rsd.  For other configs we need to add the baseline rsd to this rsd.
            # (See comments for speedup calculations).
            rsd = if config == @baseline_config
                baseline_rsd
                else
                Math.sqrt(baseline_rsd ** 2 + rel_stddev(values) ** 2)
                end
            # Use (this / baseline) so that bar goes up as value (mem usage) of *this* goes up.
            @peak_mb_relative_by_config[config].push [this_config_mean_mb / baseline_mean, rsd]
          end
        end

        # Here we use @with_yjit_config and @no_jit_config directly (not @baseline_config)
        # to compare the memory difference of yjit vs no_jit on the same version.

        yjit_mem_usage = @peak_mem_by_config[@with_yjit_config][benchmark_name].sum
        no_jit_mem_usage = @peak_mem_by_config[@no_jit_config][benchmark_name].sum
        @mem_overhead_factor_by_benchmark[idx] = (yjit_mem_usage.to_f / no_jit_mem_usage) - 1.0

        # Round MiB upward, even with a single byte used, since we crash if the block isn't allocated.
        inline_mib = ((@yjit_stats[benchmark_name][0]["inline_code_size"] + (one_mib - 1))/one_mib).to_i
        outline_mib = ((@yjit_stats[benchmark_name][0]["outlined_code_size"] + (one_mib - 1))/one_mib).to_i

        @inline_mem_used.push inline_mib
        @outline_mem_used.push outline_mib
      end
    end
  end
end
