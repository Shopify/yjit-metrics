# frozen_string_literal: true

module YJITMetrics
  # FIXME: Do we need this?
  # Default settings for Benchmark CI.
  # This is used by benchmark_and_update.rb for CI reporting directly.
  # It's also used by the VariableWarmupReport when selecting appropriate
  # benchmarking settings. This is only for the default ruby-bench benchmarks.
  DEFAULT_YJIT_BENCH_CI_SETTINGS = {
    # Config names and config-specific settings
    "configs" => {
      # Each config controls warmup individually. But the number of real iterations needs
      # to match across all configs, so it's not set per-config.
      "x86_64_yjit_stats" => {
      },
      "x86_64_prod_ruby_no_jit" => {
      },
      "x86_64_prod_ruby_with_yjit" => {
      },
      "x86_64_prev_ruby_no_jit" => {
      },
      "x86_64_prev_ruby_yjit" => {
      },
      "aarch64_yjit_stats" => {
      },
      "aarch64_prod_ruby_no_jit" => {
      },
      "aarch64_prod_ruby_with_yjit" => {
      },
      "aarch64_prev_ruby_no_jit" => {
      },
      "aarch64_prev_ruby_yjit" => {
      },
    },
    # Non-config-specific settings
    "min_bench_itrs" => 15,
    "min_bench_time" => 20,
    "min_warmup_itrs" => 5,
    "max_warmup_itrs" => 30,
    "max_itr_time" => 8 * 3600,  # Used to stop at 300 minutes to avoid GHActions 360 min cutoff. Now the 7pm run needs to not overlap the 6am run.
  }
end
