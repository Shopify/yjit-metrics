# frozen_string_literal: true

require_relative "../report"

module YJITMetrics
  class YJITStatsReport < Report
    attr_reader :stats_config

    # The report only runs on benchmarks that match the ones specified *and* that are present in
    # the data files. This is that final list of benchmarks.
    attr_reader :benchmark_names

    # If we can't get stats data, we can't usefully run this report.
    attr_reader :inactive

    def initialize(stats_configs, results, benchmarks: [])
      raise("No stats configs given for YJIT stats report!") if stats_configs.empty?

      super

      bad_configs = stats_configs - results.available_configs
      raise "Unknown configurations in report: #{bad_configs.inspect}!" unless bad_configs.empty?

      # Take the specified reporting configurations and filter by which ones contain YJIT stats. The result should
      # be a single configuration to report on.
      filtered_stats_configs = results.configs_containing_full_yjit_stats & stats_configs

      # The surrounding code seems to be from before we started running multiple platforms,
      # so if that's what we have (multiple platforms) just limit to one so we can get the report.
      if filtered_stats_configs.size > 1
        # If the configs are the same but for different platforms, pick one.
        # This regexp should be a constant but when this file is loaded
        # the PLATFORMS constant hasn't been defined yet.
        if filtered_stats_configs.map { |c| YJITMetrics.config_without_platform(c) }.uniq.size == 1
        x86 = filtered_stats_configs.select { |c| c.start_with?("x86_64") }
        filtered_stats_configs = x86 unless x86.empty?
        end
      end

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
        entries = relevant_stats.map { |dataset| dataset[stats_key] }.compact
        if entries[0].is_a?(Integer)
          yjit_data[stats_key] = entries.sum(0)
        elsif entries[0].is_a?(Float)
          yjit_data[stats_key] = entries.sum(0.0)
        elsif entries[0].is_a?(Hash) && entries[0].empty? || entries[0].values[0].is_a?(Integer)
          yjit_data[stats_key] = {}
          sub_keys = entries.flat_map(&:keys).uniq
          sub_keys.each do |sub_key|
          yjit_data[stats_key][sub_key] = entries.sum(0) { |entry| entry[sub_key] }
          end
        else
          raise "Failing for #{stats_key.inspect} with unknown entry type #{entries[0].class}!"
        end
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

    def exit_report_for_benchmarks(benchmarks)
      # Bindings for use inside ERB report template
      stats = combined_stats_data_for_benchmarks(benchmarks)
      side_exits = total_exit_count(stats)
      total_exits = side_exits + stats["leave_interp_return"]

      # Number of instructions that finish executing in YJIT
      retired_in_yjit = (stats["exec_instruction"] || stats["yjit_insns_count"]) - side_exits

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
        text.concat("  (all relevant counters are zero)")
        return text
      end

      counters = counters.to_a
      counters.sort_by! { |_, counter_value| counter_value }
      longest_name_length = counters.max_by { |name, _| name.length }.first.length
      total = counters.sum { |_, counter_value| counter_value }

      counters.reverse_each do |name, value|
        percentage = value.to_f * 100 / total
        text.concat("  %*s %10d (%4.1f%%)\n" % [longest_name_length, name, value, percentage])
      end

      text
    end
  end
end
