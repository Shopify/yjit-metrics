# frozen_string_literal: true
require_relative "./bloggable_single_report"

# This report is to compare YJIT's speedup versus other Rubies for a single run or block of runs,
# with a single YJIT head-of-master.
module YJITMetrics
  class BlogYJITStatsReport < BloggableSingleReport
    def self.report_name
      "blog_yjit_stats"
    end

    def self.report_extensions
      ["html"]
    end

    def set_extra_info(info)
      super

      if info[:timestamps]
        @timestamps = info[:timestamps]
        if @timestamps.size != 1
          raise "WE REQUIRE A SINGLE TIMESTAMP FOR THIS REPORT RIGHT NOW!"
        end
        @timestamp_str = @timestamps[0].strftime("%Y-%m-%d-%H%M%S")
      end
    end

    def initialize(config_names, results, benchmarks: [])
      # Set up the parent class, look up relevant data
      super
      return if @inactive

      # This report can just run with one platform's data and everything's fine.
      # The stats data should be basically identical on other platforms.
      look_up_data_by_ruby only_platforms: results.platforms[0]

      # Sort benchmarks by headline/micro category, then alphabetically
      @benchmark_names.sort_by! { |bench_name|
        [ benchmark_category_index(bench_name),
          bench_name ] }

      @headings_with_tooltips = {
        "bench" => "Benchmark name",
        "Exit Report" => "Link to a generated YJIT-stats-style exit report",
        "Inline" => "Bytes of inlined code generated",
        "Outlined" => "Bytes of outlined code generated",
        "Comp iSeqs" => "Number of compiled iSeqs (methods)",
        "Comp Blocks" => "Number of compiled blocks",
        "Inval" => "Number of methods or blocks invalidated",
        "Inval Ratio" => "Number of blocks invalidated over number of blocks compiled",
        "Bind Alloc" => "Number of Ruby bindings allocated",
        "Bind Set" => "Number of variables set via bindings",
        "Const Bumps" => "Number of times Ruby clears its internal constant cache",
        "Compile Time MS" => "Time YJIT spent compiling blocks in Milliseconds",
      }

      # Col formats are only used when formatting entries for a text table, not for CSV
      @col_formats = @headings_with_tooltips.keys.map { "%s" }
    end

    # Listed on the details page
    def details_report_table_data
      @benchmark_names.map.with_index do |bench_name, idx|
        bench_desc = ( BENCHMARK_METADATA[bench_name] && BENCHMARK_METADATA[bench_name][:desc] )  || "(no description available)"
        bench_desc = bench_desc.gsub('"' , "&quot;")
        if BENCHMARK_METADATA[bench_name] && BENCHMARK_METADATA[bench_name][:single_file]
          bench_url = "https://github.com/Shopify/yjit-bench/blob/main/benchmarks/#{bench_name}.rb"
        else
          bench_url = "https://github.com/Shopify/yjit-bench/blob/main/benchmarks/#{bench_name}/benchmark.rb"
        end

        exit_report_url = "/reports/benchmarks/blog_exit_reports_#{@timestamp_str}.#{bench_name}.txt"

        bench_stats = @yjit_stats[bench_name][0]

        fmt_inval_ratio = "?"
        if bench_stats["invalidation_count"] && bench_stats["compiled_block_count"]
          inval_ratio = bench_stats["invalidation_count"].to_f / bench_stats["compiled_block_count"]
          fmt_inval_ratio = "%d%%" % (inval_ratio * 100.0).to_i
        end

        [ "<a href=\"#{bench_url}\" title=\"#{bench_desc}\">#{bench_name}</a>",
          "<a href=\"#{exit_report_url}\">(click)</a>",
          bench_stats["inline_code_size"],
          bench_stats["outlined_code_size"],
          bench_stats["compiled_iseq_count"],
          bench_stats["compiled_block_count"],
          bench_stats["invalidation_count"],
          fmt_inval_ratio,
          bench_stats["binding_allocations"],
          bench_stats["binding_set"],
          bench_stats["constant_state_bumps"],
          (bench_stats["compile_time_ns"] / 1_000_000.0),
        ]

      end
    end

    def write_file(filename)
      if @inactive
        # Can't get stats? Write an empty file.
        self.class.report_extensions.each do |ext|
          File.open(filename + ".#{ext}", "w") { |f| f.write("") }
        end
        return
      end

      # Memory details report, with tables and text descriptions
      script_template = ERB.new File.read(__dir__ + "/../report_templates/blog_yjit_stats.html.erb")
      html_output = script_template.result(binding)
      File.open(filename + ".html", "w") { |f| f.write(html_output) }
    end
  end
end
