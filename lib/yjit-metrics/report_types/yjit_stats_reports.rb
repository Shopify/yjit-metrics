class YJITMetrics::YJITStatsReport < YJITMetrics::Report
    attr_reader :stats_config

    # The report only runs on benchmarks that match the ones specified *and* that are present in
    # the data files. This is that final list of benchmarks.
    attr_reader :benchmark_names

    # If we can't get stats data, we can't usefully run this report.
    attr_reader :inactive

    def initialize(stats_configs, results, benchmarks: [])
        super

        bad_configs = stats_configs - results.available_configs
        raise "Unknown configurations in report: #{bad_configs.inspect}!" unless bad_configs.empty?

        # Take the specified reporting configurations and filter by which ones contain YJIT stats. The result should
        # be a single configuration to report on.
        filtered_stats_configs = results.configs_containing_full_yjit_stats & stats_configs
        @inactive = false
        if filtered_stats_configs.empty?
            puts "We didn't find any config with YJIT stats among #{stats_configs.inspect}!" if filtered_stats_configs.empty?
            @inactive = true
            return
        elsif filtered_stats_configs.size > 1
            puts "We found more than one config with YJIT stats (#{filtered_stats_configs.inspect}) in this result set!"
            @inactive = true
            return
        end
        @stats_config = filtered_stats_configs.first

        @result_set = results
        @only_benchmarks = benchmarks

        bench_yjit_stats = @result_set.yjit_stats_for_config_by_benchmark(@stats_config)
        raise("Config #{@stats_config.inspect} collected no YJIT stats!") if bench_yjit_stats.nil? || bench_yjit_stats.values.all?(&:empty?)

        # Only run benchmarks if there is no list of "only run these" benchmarks, or if the benchmark name starts with one of the list elements
        @benchmark_names = filter_benchmark_names(bench_yjit_stats.keys)
    end

    # Pretend that all these listed benchmarks ran inside a single Ruby process. Combine their statistics, as though you were
    # about to print an exit report.
    def combined_stats_data_for_benchmarks(benchmark_names)
        raise("Can't query stats for an inactive stats-based report!") if @inactive

        unless benchmark_names.all? { |benchmark_name| @benchmark_names.include?(benchmark_name) }
            raise "No data found for benchmark #{benchmark_name.inspect}!"
        end

        all_yjit_stats = @result_set.yjit_stats_for_config_by_benchmark(@stats_config)
        relevant_stats = benchmark_names.flat_map { |benchmark_name| all_yjit_stats[benchmark_name] }.select { |data| !data.empty? }

        if relevant_stats.empty?
            raise "No YJIT stats data found for benchmarks: #{benchmark_names.inspect}!"
        end

        # For each key in the YJIT statistics, add up the value for that key in all datasets. Note: all_stats is a non-numeric key.
        yjit_stats_keys = relevant_stats[0].keys - ["all_stats"]
        yjit_data = {}
        yjit_stats_keys.each do |stats_key|
            # Unknown keys default to 0
            yjit_data[stats_key] = relevant_stats.map { |dataset| dataset[stats_key] || 0 }.sum
        end
        yjit_data
    end

    # Equivalent of yjit.rb:total_exit_count
    def total_exit_count(stats, prefix: "exit_")
        total = 0
        stats.each do |k,v|
            total += v if k.start_with?(prefix)
        end
        total
    end

    # Equivalent of yjit.rb:runtime_stats, with some differences
    def exit_report_for_benchmarks(benchmarks)
        # Bindings for use inside ERB report template
        stats = combined_stats_data_for_benchmarks(benchmarks)
        side_exits = total_exit_count(stats)
        total_exits = side_exits + stats["leave_interp_return"]

        # Number of instructions that finish executing in YJIT
        retired_in_yjit = stats["exec_instruction"] - side_exits

        # Average length of instruction sequences executed by YJIT
        avg_len_in_yjit = retired_in_yjit.to_f / total_exits

        # Proportion of instructions that retire in YJIT
        total_insns_count = retired_in_yjit + stats["vm_insns_count"]
        yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count

        # Older YJIT didn't have these in the recorded stats
        stats["total_insns_count"] = total_insns_count unless stats["total_insns_count"]
        stats["ratio_in_yjit"] = yjit_ratio_pct unless stats["ratio_in_yjit"]
        stats["side_exit_count"] = side_exits unless stats["side_exit_count"]
        stats["total_exit_count"] = total_exits unless stats["total_exit_count"]
        stats["avg_len_in_yjit"] = avg_len_in_yjit unless stats["avg_len_in_yjit"]

        printed_stats(stats)
    end

    # Equivalent of yjit.rb:_print_stats - very differently structured
    def printed_stats(stats)
        text = ""

        ({
            'send_' => 'method call exit reasons: ',
            'invokeblock_' => 'invokeblock exit reasons: ',
            'invokesuper_' => 'invokesuper exit reasons: ',
            'leave_' => 'leave exit reasons: ',
            'gbpp_' => 'getblockparamproxy exit reasons: ',
            'getivar_' => 'getinstancevariable exit reasons: ',
            'setivar_' => 'setinstancevariable exit reasons: ',
            'oaref_' => 'opt_aref exit reasons: ',
            'expandarray_' => 'expandarray exit reasons: ',
            'opt_getinlinecache_' => 'opt_getinlinecache exit reasons: ',
            'invalidate_' => 'invalidation reasons: ',
        }).each do |prefix, prompt|
            text += counters_section(stats, prefix: prefix, prompt: prompt)
        end

        # Number of failed compiler invocations - may be nil for older YJIT
        compilation_failure = stats[:compilation_failure] || 0

        text += "compilation_failure:   " + ("%10d" % compilation_failure) if compilation_failure != 0

        [ :compiled_iseq_count, :compiled_block_count, :compiled_branch_count, :block_next_count, :defer_count, :freed_iseq_count,
          :invalidation_count, :constant_state_bumps, :inline_code_size, :outlined_code_size, :freed_code_size,
          :code_region_size, :yjit_alloc_size, :live_page_count, :freed_page_count, :code_gc_count, :num_gc_obj_refs,
          :object_shape_count, :side_exit_count, :total_exit_count, :total_insns_count, :vm_insns_count ].each do |metric|
            if stats.has_key?(metric.to_s) # Some keys may not have been introduced yet for a given Ruby version
                text += ("%-23s" % (metric.to_s + ":")) + ("%10d" % stats[metric.to_s]) + "\n"
            end
        end

        if stats.has_key?("exec_instruction")
            text += "yjit_insns_count:      " + ("%10d" % stats["exec_instruction"]) + "\n"
        end

        [ "ratio_in_yjit", "avg_len_in_yjit" ].each do |metric|
            text += ("%-23s" % (metric + ":")) + ("%10d" % stats[metric]) + "\n"
        end

        text += "\n"
        text += sorted_exit_counts(stats, prefix: "exit_")
    end

    # Equivalent of yjit.rb:print_sorted_exit_counts
    def sorted_exit_counts(stats, prefix:, how_many: 20, left_pad: 4)
      prefix_text = ""

      exits = []
      stats.each do |k, v|
        if k.start_with?(prefix)
          exits.push [k.to_s.delete_prefix(prefix), v]
        end
      end

      exits = exits.select { |_name, count| count > 0 }.sort_by { |_name, count| -count }.first(how_many)
      total_exits = total_exit_count(stats)

      if total_exits > 0
        top_n_total = exits.sum { |name, count| count }
        top_n_exit_pct = 100.0 * top_n_total / total_exits

        prefix_text.concat "Top-#{exits.size} most frequent exit ops (#{"%.1f" % top_n_exit_pct}% of exits):\n"

        longest_insn_name_len = exits.map { |name, count| name.length }.max
        exits.each do |name, count|
          padding = longest_insn_name_len + left_pad
          padded_name = "%#{padding}s" % name
          padded_count = "%10d" % count
          percent = 100.0 * count / total_exits
          formatted_percent = "%.1f" % percent
          prefix_text.concat("#{padded_name}: #{padded_count} (#{formatted_percent}%)\n")
        end
      else
        prefix_text.concat "total_exits:           " + ("%10d" % total_exits) + "\n"
      end

      prefix_text
    end

    # Equivalent of yjit.rb:print_counters
    def counters_section(counters, prefix:, prompt:)
        text = prompt + "\n"

        counters = counters.filter { |key, _| key.start_with?(prefix) }
        counters.filter! { |_, value| value != 0 }
        counters.transform_keys! { |key| key.to_s.delete_prefix(prefix) }

        if counters.empty?
            text.concat("    (all relevant counters are zero)\n")
            return text
        end

        counters = counters.to_a
        counters.sort_by! { |_, counter_value| counter_value }
        longest_name_length = counters.max_by { |name, _| name.length }.first.length
        total = counters.sum { |_, counter_value| counter_value }

        counters.reverse_each do |name, value|
            percentage = value.fdiv(total) * 100
            text.concat("    %*s %10d (%4.1f%%)\n" % [longest_name_length, name, value, percentage])
        end

        text
    end

end

# This is intended to match the exit report printed by debug YJIT when stats are turned on.
class YJITMetrics::YJITStatsExitReport < YJITMetrics::YJITStatsReport
    def self.report_name
        "yjit_stats_default"
    end

    def to_s
        exit_report_for_benchmarks(@benchmark_names)
    end

    def write_file(filename)
        text_output = self.to_s
        File.open(filename + ".txt", "w") { |f| f.write(text_output) }
    end
end

# Note: this is now unused in normal operation, but is still in unit tests for reporting.
# This report is to compare YJIT's time-in-JIT versus its speedup for various benchmarks.
class YJITMetrics::YJITStatsMultiRubyReport < YJITMetrics::YJITStatsReport
    def self.report_name
        "yjit_stats_multi"
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the YJIT stats parent class
        super

        # We've figured out which config is the YJIT stats. Now which one is production stats with YJIT turned on?
        # For now, let's assume it contains the string "with_yjit".
        alt_configs = config_names - [ @stats_config ]
        with_yjit_configs = alt_configs.select { |name| name["with_yjit"] }
        raise "We found more than one candidate with-YJIT config (#{with_yjit_configs.inspect}) in this result set!" if with_yjit_configs.size > 1
        raise "We didn't find any config that looked like a with-YJIT config among #{config_names.inspect}!" if with_yjit_configs.empty?
        @with_yjit_config = with_yjit_configs[0]

        # Now which one has no YJIT? Let's assume it contains the string "no_jit".
        alt_configs -= with_yjit_configs
        no_yjit_configs = alt_configs.select { |name| name["no_jit"] }
        raise "We found more than one candidate no-YJIT config (#{no_yjit_configs.inspect}) in this result set!" if no_yjit_configs.size > 1
        raise "We didn't find any config that looked like a no-YJIT config among #{config_names.inspect}!" if no_yjit_configs.empty?
        @no_yjit_config = no_yjit_configs[0]

        # Let's calculate some report data
        times_by_config = {}
        [ @with_yjit_config, @no_yjit_config ].each { |config| times_by_config[config] = results.times_for_config_by_benchmark(config) }
        @headings = [ "bench", @with_yjit_config + " (ms)", "speedup (%)", "% in YJIT" ]
        @col_formats = [ "%s", "%.1f", "%.2f", "%.2f" ]

        @benchmark_names = filter_benchmark_names(times_by_config[@no_yjit_config].keys)

        times_by_config.each do |config_name, results|
            raise("No results for configuration #{config_name.inspect} in PerBenchRubyComparison!") if results.nil? || results.empty?
        end

        stats = results.yjit_stats_for_config_by_benchmark(@stats_config)

        @report_data = @benchmark_names.map do |benchmark_name|
            no_yjit_config_times = times_by_config[@no_yjit_config][benchmark_name]
            no_yjit_mean = mean(no_yjit_config_times)
            with_yjit_config_times = times_by_config[@with_yjit_config][benchmark_name]
            with_yjit_mean = mean(with_yjit_config_times)
            yjit_ratio = no_yjit_mean / with_yjit_mean
            yjit_speedup_pct = (yjit_ratio - 1.0) * 100.0

            # A benchmark run may well return multiple sets of YJIT stats per benchmark name/type.
            # For these calculations we just add all relevant counters together.
            this_bench_stats = combined_stats_data_for_benchmarks([benchmark_name])

            side_exits = total_exit_count(this_bench_stats)
            retired_in_yjit = this_bench_stats["exec_instruction"] - side_exits
            total_insns_count = retired_in_yjit + this_bench_stats["vm_insns_count"]
            yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count

            [ benchmark_name, with_yjit_mean, yjit_speedup_pct, yjit_ratio_pct ]
        end
    end

    def to_s
        format_as_table(@headings, @col_formats, @report_data)
    end

    def write_file(filename)
        text_output = self.to_s
        File.open(filename + ".txt", "w") { |f| f.write(text_output) }
    end
end
