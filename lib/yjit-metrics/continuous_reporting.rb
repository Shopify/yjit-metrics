require "fileutils"

module YJITMetrics
  module ContinuousReporting
    # Dir in which yjit-metrics, yjit-bench, etc are cloned
    YM_ROOT_DIR = File.expand_path(File.join(__dir__, "../../.."))

    # This repo.
    YM_REPO = File.join(YM_ROOT_DIR, "yjit-metrics")

    def self.find_dir(base)
      above = File.join(YM_ROOT_DIR, base)
      below = File.join(YM_REPO, "build", base)
      below_exist = File.exist?(below)

      # This will be true on the server, currently.
      return above if File.exist?(above) && !below_exist

      FileUtils.mkdir_p(below) unless below_exist
      below
    end

    # Raw benchmark data gets written to a platform- and date-specific subdirectory, but will often be read from multiple subdirectories
    RAW_BENCHMARK_ROOT = find_dir("raw-benchmark-data")

    # We cache all the built per-run reports, which can take a long time to rebuild
    BUILT_REPORTS_ROOT = find_dir("built-yjit-reports")

    # We have a separate repo for the final HTML, because creating the new orphan branch is fiddly
    GHPAGES_REPO = find_dir("ghpages-yjit-metrics")
  end
end
