# frozen_string_literal: true
require_relative "./yjit_stats_report"

module YJITMetrics
  # This is intended to match the exit report printed by debug YJIT when stats are turned on.
  # Note that this is somewhat complex to keep up to date. We don't store literal YJIT exit
  # reports. In fact, exit reports are often meant to mimic a situation that never existed,
  # where multiple runs are combined and then a hypothetical exit report is printed for them.
  # So we don't store a real, literal exit report, which sometimes never happened.
  #
  # Instead we periodically update the logic and templates for the exit reports to match
  # the current YJIT stats data. Keep in mind that older YJIT stats data often has different
  # stats -- including renamed stats, or stats not collected for years, etc. So that means
  # the code for exit reports may need to be more robust than the code from YJIT, which
  # only has to deal with stats from its own exact YJIT version.
  #
  # Despite that, the logic here intentionally follows the structure of YJIT's own exit
  # reports so that it's not too difficult to update. Make sure to rebuild all the old
  # exit reports when you update this to ensure that you don't have any that crash because
  # of missing or renamed stats.
  class YJITStatsExitReport < YJITStatsReport
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
end
