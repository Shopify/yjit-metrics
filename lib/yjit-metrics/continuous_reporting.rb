module YJITMetrics
  module ContinuousReporting
    # Dir in which yjit-metrics, yjit-bench, etc are cloned
    YM_ROOT_DIR = File.expand_path(File.join(__dir__, "../../.."))

    # Clone of yjit-metrics repo, pages branch
    YJIT_METRICS_PAGES_DIR = File.expand_path File.join(YM_ROOT_DIR, "yjit-metrics-pages")

    # Raw benchmark data gets written to a platform- and date-specific subdirectory, but will often be read from multiple subdirectories
    RAW_BENCHMARK_ROOT = File.join(YM_ROOT_DIR, "raw-benchmark-data")

    # This contains Jekyll source files of various kinds - everything but the built reports
    RAW_REPORTS_ROOT = File.join(YM_ROOT_DIR, "raw-yjit-reports")

    # We cache all the built per-run reports, which can take a long time to rebuild
    BUILT_REPORTS_ROOT = File.join(YM_ROOT_DIR, "built-yjit-reports")

    # We have a separate repo for the final HTML, because creating the new orphan branch is fiddly
    GHPAGES_REPO = File.join(YM_ROOT_DIR, "ghpages-yjit-metrics")
  end
end
