# frozen_string_literal: true

require_relative "./stats"
require_relative "./theme"

# Encapsulate multiple benchmark runs across multiple Ruby configurations.
# Do simple calculations, reporting and file I/O.
#
# Note that a JSON file with many results can be quite large.
# Normally it's appropriate to store raw data as multiple JSON files
# that contain one set of runs each. Large multi-Ruby datasets
# may not be practical to save as full raw data.
module YJITMetrics
  class ResultSet
    include YJITMetrics::Stats

    def initialize
      @times = {}
      @warmups = {}
      @benchmark_metadata = {}
      @ruby_metadata = {}
      @yjit_stats = {}
      @peak_mem = {}
      @empty = true
    end

    def empty?
      @empty
    end

    def config_names
      @times.keys
    end

    def platforms
      @ruby_metadata.map { |config, hash| hash["platform"] }.uniq
    end

    # "Fragments" are, in effect, a quick human-readable way to summarise a particular
    # compile-time-plus-run-time Ruby configuration. Doing this in general would
    # require serious AI, but we don't need it in general. We have a few specific
    # cases we care about.
    #
    # Right now we're just checking the config name. It would be better, but harder,
    # to actually verify the configuration from the config's Ruby metadata (and other
    # metadata?) and make sure the config does what it's labelled as.
    CONFIG_NAME_SPECIAL_CASE_FRAGMENTS = {
      "prod_ruby_with_yjit" => "YJIT <version>",
      "prev_ruby_yjit" => "YJIT <version>",
      "prod_ruby_with_mjit" => "MJIT",
      "ruby_30_with_mjit" => "MJIT-3.0",
      "prod_ruby_no_jit" => "CRuby <version>",
      "prev_ruby_no_jit" => "CRuby <version>",
      "truffleruby" => "TruffleRuby",
      "yjit_stats" => "YJIT <version> Stats",
    }
    def table_of_configs_by_fragment(configs)
      configs_by_fragment = {}
      frag_by_length = CONFIG_NAME_SPECIAL_CASE_FRAGMENTS.keys.sort_by { |k| -k.length } # Sort longest-first
      configs.each do |config|
        longest_frag = frag_by_length.detect { |k| config.include?(k) }
        unless longest_frag
          raise "Trying to sort config #{config.inspect} by fragment, but no fragment matches!"
        end
        configs_by_fragment[longest_frag] ||= []
        configs_by_fragment[longest_frag] << config
      end
      configs_by_fragment
    end

    # Add a table of configurations, distinguished by platform, compile-time config, runtime config and whatever
    # else we can determine from config names and/or result data. Only include configurations for which we have
    # results. Order by the req_configs order, if supplied, otherwise by order results were added in (internal
    # hash table order.)
    # NOTE: This is currently only used by variable_warmup_report which discards the actual human names
    # (it gets used to select and order the configs).
    def configs_with_human_names(req_configs = nil)
      # Only use requested configs for which we have data
      if req_configs
        # Preserve req_configs order
        c_n = config_names
        only_configs = req_configs.select {|config| c_n.include?(config) }
      else
        only_configs = config_names()
      end

      if only_configs.size == 0
        puts "No requested configurations have any data..."
        puts "Requested configurations: #{req_configs.inspect} #{req_configs == nil ? "(nil means use all)" : ""}"
        puts "Configs we have data for: #{@times.keys.inspect}"
        raise("Can't generate human names table without any configurations!")
      end

      configs_by_platform = {}
      only_configs.each do |config|
        config_platform = @ruby_metadata[config]["platform"]
        configs_by_platform[config_platform] ||= []
        configs_by_platform[config_platform] << config
      end

      # TODO: Get rid of this branch and the next and just use "human_name platform" consistently.

      # If each configuration only exists for a single platform, we'll use the platform names as human-readable names.
      if configs_by_platform.values.map(&:size).max == 1
        out = {}
        # Order output by req_config
        req_configs.each do |config|
          platform = configs_by_platform.detect { |platform, plat_configs| plat_configs.include?(config) }
          out[platform] = config
        end
        return out
      end

      # If all configurations are on the *same* platform, we'll use names like YJIT and MJIT and MJIT(3.0)
      if configs_by_platform.size == 1
        # Sort list of configs by what fragments (Ruby version plus runtime config) they contain
        by_fragment = table_of_configs_by_fragment(only_configs)

        # If no two configs have the same Ruby version plus runtime config, then that's how we'll name them.
        frags_with_multiple_configs = by_fragment.keys.select { |frag| (by_fragment[frag] || []).length > 1 }
        if frags_with_multiple_configs.empty?
          out = {}
          # Order by req_configs
          req_configs.each do |config|
            fragment = by_fragment.detect { |frag, configs| configs[0] == config }.first
            human_name = insert_version_for_config(CONFIG_NAME_SPECIAL_CASE_FRAGMENTS[fragment], config)
            out[human_name] = config
          end
          return out
        end

        unsortable_configs = frags_with_multiple_configs.flat_map { |frag| by_fragment[frag] }
        puts "Fragments with multiple configs: #{frags_with_multiple_configs.inspect}"
        puts "Configs we can't sort by fragment: #{unsortable_configs.inspect}"
        raise "We only have one platform, but we can't sort by fragment... Need finer distinctions!"
      end

      # Okay. We have at least two platforms. Now things get stickier.
      by_platform_and_fragment = {}
      configs_by_platform.each do |platform, configs|
        by_platform_and_fragment[platform] = table_of_configs_by_fragment(configs)
      end
      hard_to_name_configs = by_platform_and_fragment.values.flat_map(&:values).select { |configs| configs.size > 1 }.inject([], &:+).uniq

      # If no configuration shares *both* platform *and* fragment, we can name by platform and fragment.
      if hard_to_name_configs.empty?
        plat_frag_table = {}
        by_platform_and_fragment.each do |platform, frag_table|
          CONFIG_NAME_SPECIAL_CASE_FRAGMENTS.each do |fragment, human_name|
            next unless frag_table[fragment]

            single_config = frag_table[fragment][0]
            human_name = insert_version_for_config(human_name, single_config)
            plat_frag_table[single_config] = "#{human_name} #{platform}"
          end
        end

        # Now reorder the table by req_configs
        out = {}
        req_configs.each do |config|
          out[plat_frag_table[config]] = config
        end
        return out
      end

      raise "Complicated case in configs_with_human_names! Hard to distinguish between: #{hard_to_name_configs.inspect}!"
    end

    # These objects have absolutely enormous internal data, and we don't want it printed out with
    # every exception.
    def inspect
      "YJITMetrics::ResultSet<#{object_id}>"
    end

    # A ResultSet normally expects to see results with this structure:
    #
    # {
    # "times" => { "benchname1" => [ 11.7, 14.5, 16.7, ... ], "benchname2" => [...], ... },
    # "benchmark_metadata" => { "benchname1" => {...}, "benchname2" => {...}, ... },
    # "ruby_metadata" => {...},
    # "yjit_stats" => { "benchname1" => [{...}, {...}...], "benchname2" => [{...}, {...}, ...] }
    # }
    #
    # Note that this input structure doesn't represent runs (subgroups of iterations),
    # such as when restarting the benchmark and doing, say, 10 groups of 300
    # iterations. To represent that, you would call this method 10 times, once per
    # run. Runs will be kept separate internally, but by default are returned as a
    # combined single array.
    #
    # Every benchmark run is assumed to come with a corresponding metadata hash
    # and (optional) hash of YJIT stats. However, there should normally only
    # be one set of Ruby metadata, not one per benchmark run. Ruby metadata is
    # assumed to be constant for a specific compiled copy of Ruby over all runs.
    def add_for_config(config_name, benchmark_results, normalize_bench_names: true, file: nil)
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

      @empty = false

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
      ruby_meta = @ruby_metadata[config_name]
      if ruby_meta != benchmark_results["ruby_metadata"] && !@printed_ruby_metadata_warning
        print "Ruby metadata is meant to *only* include information that should always be\n" +
          "  the same for the same Ruby executable. Please verify that you have not added\n" +
          "  inappropriate Ruby metadata or accidentally used the same name for two\n" +
          "  different Ruby executables. (Additional mismatches in this result set won't show warnings.)\n"
        puts "Metadata 1: #{ruby_meta.inspect}"
        puts "Metadata 2: #{benchmark_results["ruby_metadata"].inspect}"
        @printed_ruby_metadata_warning = true
      end
      unless ruby_meta["arch"]
        # Our harness didn't record arch until adding ARM64 support. If a collected data file doesn't set it,
        # autodetect from RUBY_DESCRIPTION. We only check x86_64 since all older data should only be on x86_64,
        # which was all we supported.
        if ruby_meta["RUBY_DESCRIPTION"].include?("x86_64")
          ruby_meta["arch"] = "x86_64-unknown"
        else
          raise "No arch provided in data file, and no x86_64 detected in RUBY_DESCRIPTION!"
        end
      end
      recognized_platforms = YJITMetrics::PLATFORMS + ["arm64"]
      ruby_meta["platform"] ||= recognized_platforms.detect { |platform| (ruby_meta["uname -a"] || "").downcase.include?(platform) }
      ruby_meta["platform"] ||= recognized_platforms.detect { |platform| (ruby_meta["arch"] || "").downcase.include?(platform) }

      raise "Uknown platform" if !ruby_meta["platform"]

      ruby_meta["platform"] = ruby_meta["platform"].sub(/^arm(\d+)$/, 'aarch\1')
      #@platform ||= ruby_meta["platform"]

      #if @platform != ruby_meta["platform"]
      #  raise "A single ResultSet may only contain data from one platform, not #{@platform.inspect} AND #{ruby_meta["platform"].inspect}!"
      #end

      @full_run ||= benchmark_results["full_run"]
      if @full_run != benchmark_results["full_run"]
        warn "The 'full_run' data should not change within the same run (#{file})!"
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
        data[benchmark_name] ||= []
        runs.each { |run| data[benchmark_name].concat(run) }
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

    def ruby_version_for_config(config)
      return unless metadata = @ruby_metadata[config]

      if (match = metadata["RUBY_DESCRIPTION"]&.match(/^(?:ruby\s+)?([0-9.]+\S*)/))
        match[1]
      else
        metadata["RUBY_VERSION"]
      end
    end

    def full_run_info
      @full_run
    end

    def insert_version_for_config(str, config)
      str.sub(/<version>/, ruby_version_for_config(config))
    end

    # What Ruby configurations does this ResultSet contain data for?
    def available_configs
      @ruby_metadata.keys
    end

    def benchmarks
      @benchmark_metadata.values.flat_map(&:keys).uniq
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
            if run[key].is_a?(Integer)
              stats[key] ||= 0
              stats[key] += run[key]
            elsif run[key].is_a?(Float)
              stats[key] ||= 0.0
              stats[key] += run[key]
            elsif run[key].is_a?(Hash)
              stats[key] ||= {}
              run[key].each do |subkey, subval|
                stats[key][subkey] ||= 0
                stats[key][subkey] += subval
              end
            else
              raise "Unexpected stat type #{run[key].class}!"
            end
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
      #"exec_instruction",  # exec_instruction changed name to yjit_insns_count -- only one of the two will be present in a dataset
      "yjit_insns_count",
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

        mem_by_bench = peak_mem_bytes_for_config_by_benchmark(config)
        times_by_bench.keys.each do |bench|
          summary[config][bench]["peak_mem_bytes"] = mem_by_bench[bench]
        end

        all_stats = combined_yjit_stats_for_config_by_benchmark(config)
        all_stats.each do |bench, stats|
          summary[config][bench]["yjit_stats"] = stats.slice(*SUMMARY_STATS)
          summary[config][bench]["yjit_stats"]["yjit_insns_count"] ||= stats["exec_instruction"]

          # Do we have full YJIT stats? If so, let's add the relevant summary bits
          if stats["all_stats"]
            out_stats = summary[config][bench]["yjit_stats"]
            out_stats["side_exits"] = stats.inject(0) { |total, (k, v)| total + (k.start_with?("exit_") ? v : 0) }
            out_stats["total_exits"] = out_stats["side_exits"] + out_stats["leave_interp_return"]
            out_stats["retired_in_yjit"] = (out_stats["exec_instruction"] || out_stats["yjit_insns_count"]) - out_stats["side_exits"]
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
end
