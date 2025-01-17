# frozen_string_literal: true

require_relative "./speed_details_report"

# This report is to compare YJIT's memory usage versus other Rubies for a single run or block of runs,
# with a single YJIT head-of-master.
module YJITMetrics
  class MemoryDetailsReport < SpeedDetailsReport
    # This report requires a platform name and can't be auto-instantiated by basic_report.rb.
    # Instead, its child report(s) can instantiate it for a specific platform.
    #def self.report_name
    #  "blog_memory_details"
    #end

    def self.report_extensions
      [ "html", "svg", "head.svg", "back.svg", "micro.svg", "csv" ]
    end

    def initialize(config_names, results, platform:, benchmarks: [])
      unless YJITMetrics::PLATFORMS.include?(platform)
        raise "Invalid platform for #{self.class.name}: #{platform.inspect}!"
      end
      @platform = platform

      # Set up the parent class, look up relevant data
      # Permit non-same-platform stats config
      config_names = config_names.select { |name| name.start_with?(platform) || name.include?("yjit_stats") }
      # FIXME: Drop the platform: platform when we stop inheriting from SpeedDetailsReport.
      super(config_names, results, platform: platform, benchmarks: benchmarks)
      return if @inactive

      look_up_data_by_ruby

      # Sort benchmarks by headline/micro category, then alphabetically
      @benchmark_names.sort_by! { |bench_name|
        [ benchmark_category_index(bench_name),
          #-@yjit_stats[bench_name][0]["compiled_iseq_count"],
          bench_name ] }

      @headings = [ "bench" ] +
        @configs_with_human_names.map { |name, config| "#{name} mem (MiB)"} +
        [ "Inline Code", "Outlined Code", "YJIT Mem overhead" ]
        #@configs_with_human_names.flat_map { |name, config| config == @baseline_config ? [] : [ "#{name} mem ratio" ] }
      # Col formats are only used when formatting entries for a text table, not for CSV
      @col_formats = [ bench_name_link_formatter ] +
        [ "%d" ] * @configs_with_human_names.size +     # Mem usage per-Ruby
        [ "%d", "%d", "%.1f%%" ]              # YJIT mem breakdown
        #[ "%.2fx" ] * (@configs_with_human_names.size - 1)  # Mem ratio per-Ruby

      calc_mem_stats_by_config
    end

    # Printed to console
    def report_table_data
      @benchmark_names.map.with_index do |bench_name, idx|
        [ bench_name ] +
          @configs_with_human_names.map { |name, config| @peak_mb_by_config[config][idx] } +
          [ @inline_mem_used[idx], @outline_mem_used[idx] ]
          #[ "#{"%d" % (@peak_mb_by_config[@with_yjit_config][idx] - 256)} + #{@inline_mem_used[idx]}/128 + #{@outline_mem_used[idx]}/128" ]
      end
    end

    # Listed on the details page
    def details_report_table_data
      @benchmark_names.map.with_index do |bench_name, idx|
        [ bench_name ] +
          @configs_with_human_names.map { |name, config| @peak_mb_by_config[config][idx] } +
          [ @inline_mem_used[idx], @outline_mem_used[idx], @mem_overhead_factor_by_benchmark[idx] * 100.0 ]
          #[ "#{"%d" % (@peak_mb_by_config[@with_yjit_config][idx] - 256)} + #{@inline_mem_used[idx]}/128 + #{@outline_mem_used[idx]}/128" ]
      end
    end

    def to_s
      # This is just used to print the table to the console
      format_as_table(@headings, @col_formats, report_table_data) +
        "\nMemory usage is in MiB (mebibytes,) rounded. Ratio is versus interpreted baseline CRuby.\n"
    end

    def html_template_path
      File.expand_path("../report_templates/blog_memory_details.html.erb", __dir__)
    end

    def relative_values_by_config_and_benchmark
      @peak_mb_relative_by_config
    end
  end
end
