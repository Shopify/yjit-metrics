# frozen_string_literal: true
require_relative "./bloggable_single_report"

module YJITMetrics
  class BlogStatsExitReports < BloggableSingleReport
    def self.report_name
      "blog_exit_reports"
    end

    def self.report_extensions
      ["bench_list.txt"]
    end

    def write_file(filename)
      if @inactive
        # Can't get stats? Write an empty file.
        self.class.report_extensions.each do |ext|
          File.open(filename + ".#{ext}", "w") { |f| f.write("") }
        end
        return
      end

      @benchmark_names.each do |bench_name|
        File.open("#{filename}.#{bench_name}.txt", "w") { |f| f.puts exit_report_for_benchmarks([bench_name]) }
      end

      # This is a file with a known name that we can look for when generating.
      File.open("#{filename}.bench_list.txt", "w") { |f| f.puts @benchmark_names.join("\n") }
    end
  end
end
