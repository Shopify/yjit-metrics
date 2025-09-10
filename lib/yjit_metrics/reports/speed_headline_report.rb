# frozen_string_literal: true

require_relative "./bloggable_single_report"

# This very small report is to give the quick headlines and summary for a YJIT comparison.
module YJITMetrics
  class SpeedHeadlineReport < BloggableSingleReport
    def self.report_name
      "blog_speed_headline"
    end

    def self.report_extensions
      ["html"]
    end

    def format_speedup(ratio)
      if ratio >= 1.01
        "%.1f%% faster than" % ((ratio - 1.0) * 100)
      elsif ratio < 0.99
        "%.1f%% slower than" % ((1.0 - ratio) * 100)
      else
        "the same speed as"
      end
    end

    def platforms
      @result_set.platforms
    end

    def yjit_bench_file_url(path)
      "https://github.com/ruby/yjit-bench/blob/#{@result_set.full_run_info&.dig("git_versions", "yjit_bench") || "main"}/#{path}"
    end

    def ruby_version(config)
      @result_set.ruby_version_for_config(config)
    end

    X86_ONLY = ENV['ALLOW_ARM_ONLY_REPORTS'] != '1'

    def initialize(config_names, results, benchmarks: [])
      # Give the headline data for x86 processors, not ARM64.
      # No x86 data? Then no headline.
      x86_configs = config_names.select { |name| name.include?("x86_64") }
      if x86_configs.empty?
        if X86_ONLY
          @no_data = true
          puts "WARNING: no x86_64 data for data: #{config_names.inspect}"
          return
        end
      else
        config_names = x86_configs
      end

      # Set up the parent class, look up relevant data
      super
      return if @inactive # Can't get stats? Bail out.

      platform = "x86_64"
      if !X86_ONLY && !results.platforms.include?(platform)
        platform = results.platforms[0]
      end
      look_up_data_by_ruby(only_platforms: [platform])

      # Sort benchmarks by headline/micro category, then alphabetically
      @benchmark_names.sort_by! { |bench_name|
        [ benchmark_category_index(bench_name),
          #-@yjit_stats[bench_name][0]["compiled_iseq_count"],
          bench_name ] }

      calc_speed_stats_by_config

      # For these ratios we compare current yjit and no_jit directly (not @baseline_config).

      # "Ratio of total times" method
      #@yjit_vs_cruby_ratio = @total_time_by_config[@no_jit_config] / @total_time_by_config[@with_yjit_config]

      headline_runtimes = headline_benchmarks.map do |bench_name|
        bench_idx = @benchmark_names.index(bench_name)

        bench_no_jit_mean = @mean_by_config[@no_jit_config][bench_idx]
        bench_yjit_mean = @mean_by_config[@with_yjit_config][bench_idx]
        prev_yjit_mean = @mean_by_config.dig(@prev_yjit_config, bench_idx)

        [ bench_yjit_mean, bench_no_jit_mean, prev_yjit_mean ]
      end
      # Geometric mean of headlining benchmarks only
      @yjit_vs_cruby_ratio = geomean headline_runtimes.map { |yjit_mean, no_jit_mean, _| no_jit_mean / yjit_mean }

      if @prev_yjit_config
        @yjit_vs_prev_yjit_ratio = geomean headline_runtimes.map { |yjit_mean, _, prev_yjit| prev_yjit / yjit_mean }
      end

      @railsbench_idx = @benchmark_names.index("railsbench")
      if @railsbench_idx
        @yjit_vs_cruby_railsbench_ratio = @mean_by_config[@no_jit_config][@railsbench_idx] / @mean_by_config[@with_yjit_config][@railsbench_idx]
        if @prev_yjit_config
          @yjit_vs_prev_yjit_railsbench_ratio = @mean_by_config[@prev_yjit_config][@railsbench_idx] / @mean_by_config[@with_yjit_config][@railsbench_idx]
        end
      end
    end

    def to_s
      return "(This run had no x86 results)" if @no_data
      script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_speed_headline.html.erb")
      script_template.result(binding) # Evaluate an Erb template with template_settings
    end

    def write_file(filename)
      if @inactive || @no_data
        # Can't get stats? Write an empty file.
        self.class.report_extensions.each do |ext|
          File.open(filename + ".#{ext}", "w") { |f| f.write("") }
        end
        return
      end

      html_output = self.to_s
      File.open(filename + ".html", "w") { |f| f.write(html_output) }
    end
  end
end
