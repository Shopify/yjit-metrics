# frozen_string_literal: true
# Count up number of iterations and warmups for each Ruby and benchmark configuration.
# As we vary these, we need to make sure people can see what settings we're using for each Ruby.
module YJITMetrics
  class IterationCountReport < BloggableSingleReport
    def self.report_name
      "iteration_count"
    end

    def self.report_extensions
      ["html"]
    end

    def initialize(config_names, results, benchmarks: [])
      # This report will only work with one platform at
      # a time, so if we have yjit_stats for x86 prefer that one.
      platform = "x86_64"
      if results.configs_containing_full_yjit_stats.any? { |c| c.start_with?(platform) }
        config_names = config_names.select { |c| c.start_with?(platform) }
      else
        platform = results.platforms.first
      end

      # Set up the parent class, look up relevant data
      super

      return if @inactive

      # This report can just run with one platform's data and everything's fine.
      # The iteration counts should be identical on other platforms.
      look_up_data_by_ruby only_platforms: [platform]

      # Sort benchmarks by headline/micro category, then alphabetically
      @benchmark_names.sort_by! { |bench_name|
        [ benchmark_category_index(bench_name),
          bench_name ] }

      @headings = [ "bench" ] +
        @configs_with_human_names.flat_map { |name, config| [ "#{name} warmups", "#{name} iters" ] }
      # Col formats are only used when formatting entries for a text table, not for CSV
      @col_formats = [ bench_name_link_formatter ] +
        [ "%d", "%d" ] * @configs_with_human_names.size   # Iterations per-Ruby-config
    end

    # Listed on the details page
    def iterations_report_table_data
      @benchmark_names.map do |bench_name|
        [ bench_name ] +
          @configs_with_human_names.flat_map do |_, config|
            if @times_by_config[config][bench_name]
              [
                @warmups_by_config[config][bench_name].size,
                @times_by_config[config][bench_name].size,
              ]
            else
              # If we didn't run this benchmark for this config, we'd like the columns to be blank.
              [ nil, nil ]
            end
          end
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
      script_template = ERB.new File.read(__dir__ + "/../report_templates/iteration_count.html.erb")
      html_output = script_template.result(binding)
      File.open(filename + ".html", "w") { |f| f.write(html_output) }
    end
  end
end
