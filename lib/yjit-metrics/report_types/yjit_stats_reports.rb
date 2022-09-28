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

    def total_exit_count(stats, prefix: "exit_")
        total = 0
        stats.each do |k,v|
            total += v if k.start_with?(prefix)
        end
        total
    end

    # The "misc" counters aren't for "can't compile" or "side exit",
    # they're for various other things.
    COUNTERS_MISC = [
        "exec_instruction",     # YJIT instructions that *start* to execute, even if they later side-exit
        "leave_interp_return",  # Number of returns to the interpreter
        "binding_allocations",  # Number of times Ruby allocates a binding (via proc.c:rb_binding_alloc)
        "binding_set",          # Number of locals modified via a binding (via proc.c:bind_local_variable_set)
    ]

    COUNTERS_SIDE_EXITS = %w(
        setivar_val_heapobject
        setivar_frozen
        setivar_idx_out_of_range
        getivar_undef
        getivar_idx_out_of_range
        getivar_se_self_not_heap
        setivar_se_self_not_heap
        oaref_arg_not_fixnum
        send_se_protected_check_failed
        send_se_cf_overflow
        leave_se_finish_frame
        leave_se_interrupt
        send_se_protected_check_failed
        )

    COUNTERS_CANT_COMPILE = %w(
        send_callsite_not_simple
        send_kw_splat
        send_bmethod
        send_zsuper_method
        send_refined_method
        send_ivar_set_method
        send_undef_method
        send_optimized_method
        send_missing_method
        send_cfunc_toomany_args
        send_cfunc_argc_mismatch
        send_cfunc_ruby_array_varg
        send_iseq_tailcall
        send_iseq_arity_error
        send_iseq_only_keywords
        send_iseq_complex_callee
        send_not_implemented_method
        send_getter_arity
        getivar_name_not_mapped
        setivar_name_not_mapped
        setivar_not_object
        oaref_argc_not_one
        )

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

        report_template = ERB.new File.read(__dir__ + "/../report_templates/yjit_stats_exit.erb")
        report_template.result(binding) # Evaluate with the local variables right here
    end

    def sorted_exit_counts(stats, prefix:, how_many: 20, left_pad: 4)
        prefix_text = ""

        exits = []
        stats.each do |k, v|
            if k.start_with?(prefix)
                exits.push [k.to_s.delete_prefix(prefix), v]
            end
        end

        exits = exits.sort_by { |name, count| [-count, name] }[0...how_many]
        side_exits = total_exit_count(stats)

        top_n_total = exits.map { |name, count| count }.sum
        top_n_exit_pct = 100.0 * top_n_total / side_exits

        prefix_text = "Top-#{how_many} most frequent exit ops (#{"%.1f" % top_n_exit_pct}% of exits):\n"

        longest_insn_name_len = exits.map { |name, count| name.length }.max
        prefix_text + exits.map do |name, count|
            padding = longest_insn_name_len + left_pad
            padded_name = "%#{padding}s" % name
            padded_count = "%10d" % count
            percent = 100.0 * count / side_exits
            formatted_percent = "%.1f" % percent
            "#{padded_name}: #{padded_count} (#{formatted_percent})"
        end.join("\n")
    end

    def counters_section(counters, prefix:, prompt:)
        text = prompt + "\n"

        counters = counters.filter { |key, _| key.start_with?(prefix) }
        counters.filter! { |_, value| value != 0 }
        counters.transform_keys! { |key| key.to_s.delete_prefix(prefix) }

        if counters.empty?
            text.concat("    (all relevant counters are zero)")
            return text
        end

        counters = counters.to_a
        counters.sort_by! { |_, counter_value| counter_value }
        longest_name_length = counters.max_by { |name, _| name.length }.first.length
        total = counters.sum { |_, counter_value| counter_value }

        counters.reverse_each do |name, value|
            percentage = value.to_f * 100 / total
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

# This report is to compare YJIT's time-in-JIT versus its speedup for various benchmarks.
class YJITMetrics::YJITStatsMultiRubyReport < YJITMetrics::YJITStatsReport
    def self.report_name
        "yjit_stats_multi"
    end

    def initialize(config_names, results, benchmarks: [])
        raise "Not yet updated for multi-platform!"

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
