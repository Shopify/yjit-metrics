require 'benchmark'
require_relative "harness-common"

# Warmup iterations
WARMUP_ITRS = ENV.fetch('WARMUP_ITRS', 15).to_i

# Minimum number of benchmarking iterations
MIN_BENCH_ITRS = ENV.fetch('MIN_BENCH_ITRS', 10).to_i

# Minimum benchmarking time in seconds
MIN_BENCH_TIME = ENV.fetch('MIN_BENCH_TIME', 10).to_f

# Takes a block as input. "values" is a special name-value that names the results after this benchmark.
def run_benchmark(_num_itrs_hint, benchmark_name: "values", &block)
  calculate_benchmark(_num_itrs_hint, benchmark_name:benchmark_name) { Benchmark.realtime { yield } }
end

# For calculate_benchmark, the block calculates a time value in fractional seconds and returns it.
# This permits benchmarks that add or subtract multiple times, or import times from a different
# runner.
def calculate_benchmark(_num_itrs_hint, benchmark_name: "values")
  require "benchmark"

  times = []
  total_time = 0
  num_itrs = 0

  # Note: this harness records *one* set of YJIT stats for all iterations
  # combined, including warmups. That's a good thing for our specific use
  # case, but would be awful for many other use cases.
  YJIT_MODULE&.reset_stats!
  begin
    time = Benchmark.realtime { yield }
    num_itrs += 1

    time_ms = (1000 * time).to_i
    print "itr \#", num_itrs, ": ", time_ms, "ms", "\n" # Minimize string allocations to reduce GC

    # We internally save the time returned by Benchmark to avoid loss of precision
    times << time
    total_time += time
  end until num_itrs >= WARMUP_ITRS + MIN_BENCH_ITRS and total_time >= MIN_BENCH_TIME

  warmup_times = times[0...WARMUP_ITRS]
  warmed_times = times[WARMUP_ITRS..-1]

  return_results("peak_mem_bytes", get_rss)
  return_results("times", warmed_times)
  return_results("warmups", warmup_times)
  return_results(:yjit_stats, YJIT_MODULE&.runtime_stats)

  return_benchmark_metadata({warmup_itrs: WARMUP_ITRS, min_bench_itrs: MIN_BENCH_ITRS, min_bench_time: MIN_BENCH_TIME})

  mean = warmed_times.sum / warmed_times.size
  stddev = Math.sqrt(warmed_times.map { |t| (t - mean) ** 2.0 }.sum / warmed_times.size)
  rel_stddev_pct = stddev / mean * 100.0
  puts "Non-warmup iteration mean time: #{"%.2f ms" % (mean * 1000.0)} +/- #{"%.2f%%" % rel_stddev_pct}"
end
