require 'benchmark'
require 'json'
require 'rbconfig'

# Warmup iterations
WARMUP_ITRS = ENV.fetch('WARMUP_ITRS', 15).to_i

# Minimum number of benchmarking iterations
MIN_BENCH_ITRS = ENV.fetch('MIN_BENCH_ITRS', 10).to_i

# Minimum benchmarking time in seconds
MIN_BENCH_TIME = ENV.fetch('MIN_BENCH_TIME', 10).to_i

TIMESTAMP = Time.now.getgm

default_path = "results-#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}-#{TIMESTAMP.strftime('%F-%H%M%S')}.json"
OUT_JSON_PATH = File.expand_path(ENV.fetch('OUT_JSON_PATH', default_path))

# Save the value of any environment variable whose name contains a string in this case-insensitive list.
# Note: this means you can store extra non-framework metadata about any run by setting an env var
# starting with YJIT_METRICS before running it.
IMPORTANT_ENV = [ "ruby", "gem", "bundle", "ld_preload", "path", "yjit_metrics" ]

IS_YJIT = Object.const_defined?(:YJIT)
HAS_YJIT_STATS = IS_YJIT && !!YJIT.runtime_stats

# Everything in ruby_metadata is supposed to be static for a single Ruby interpreter.
# It shouldn't include timestamps or other data that changes from run to run.
def ruby_metadata
    {
        "RUBY_VERSION" => RUBY_VERSION,
        "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
        "RUBY_ENGINE" => RUBY_ENGINE,
        "which ruby" => `which ruby`,
        "hostname" => `hostname`,
        "ec2 instance id" => `wget -q --timeout 1 --tries 2 -O - http://169.254.169.254/latest/meta-data/instance-id`,
        "ec2 instance type" => `wget -q --timeout 1 --tries 2 -O - http://169.254.169.254/latest/meta-data/instance-type`,

        # Ruby compile-time settings: do we want to record more of them?
        "RbConfig configure_args" => RbConfig::CONFIG["configure_args"],
    }
end

# We should flush output indicating progress even if we're not hooked up to a tty (e.g. nohup)
STDOUT.sync = true

# Takes a block as input
def run_benchmark(num_itrs_hint)
  times = []
  total_time = 0
  num_itrs = 0

  # Note: this harness records *one* set of YJIT stats for all iterations
  # combined, including warmups. That's a good thing for our specific use
  # case, but would be awful for many other use cases.
  YJIT.reset_stats! if HAS_YJIT_STATS
  begin
    time = Benchmark.realtime { yield }
    num_itrs += 1

    time_ms = (1000 * time).to_i
    print "itr \#", num_itrs, ": ", time_ms, "ms", "\n" # Minimize string allocations to reduce GC

    # NOTE: we may want to preallocate an array and avoid append
    # We internally save the time in seconds to avoid loss of precision
    times << time
    total_time += time
  end until num_itrs >= WARMUP_ITRS + MIN_BENCH_ITRS and total_time >= MIN_BENCH_TIME
  yjit_stats = HAS_YJIT_STATS ? YJIT.runtime_stats : nil

  out_env_keys = ENV.keys.select { |k| IMPORTANT_ENV.any? { |s| k.downcase[s] } }
  out_env = {}
  out_env_keys.each { |k| out_env[k] = ENV[k] }

  warmup_times = times[0...WARMUP_ITRS]
  warmed_times = times[WARMUP_ITRS..-1]

  out_data = {
    times: warmed_times,
    warmups: warmup_times,
    benchmark_metadata: {
        warmup_itrs: WARMUP_ITRS,
        min_bench_itrs: MIN_BENCH_ITRS,
        min_bench_time: MIN_BENCH_TIME,
        command_line: ARGV,
        env: out_env,
        loaded_gems: Gem.loaded_specs.map { |name, spec| [ name, spec.version.to_s ] },
    },
    ruby_metadata: ruby_metadata,
  }
  out_data[:yjit_stats] = YJIT.runtime_stats if HAS_YJIT_STATS
  File.open(OUT_JSON_PATH, "w") { |f| f.write(JSON.generate(out_data)) }
end
