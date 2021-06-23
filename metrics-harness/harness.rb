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

puts RUBY_DESCRIPTION

# Save the value of any environment variable whose name contains a string in this list.
IMPORTANT_ENV = [ "ruby", "gem", "bundle", "ld_preload", "path" ]

IS_YJIT = Object.const_defined?(:YJIT)
HAS_YJIT_STATS = IS_YJIT && !!YJIT.runtime_stats

def ruby_metadata
    out_env_keys = ENV.keys.select { |k| IMPORTANT_ENV.any? { |s| k.downcase[s] } }
    out_env = {}
    out_env_keys.each { |k| out_env[k] = ENV[k] }

    {
        "RUBY_VERSION" => RUBY_VERSION,
        "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
        "RUBY_ENGINE" => RUBY_ENGINE,
        "which ruby" => `which ruby`,
        "hostname" => `hostname`,
        "env" => out_env,
        "loaded gems" => Gem.loaded_specs.map { |name, spec| [ name, spec.version.to_s ] },
        # TODO: do we expect to combine or compare results across multiple hosts?
        #"ec2 instance id" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`,
        #"ec2 instance type" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-type`,

        # Ruby compile-time settings: do we want to record more of them?
        "RbConfig configure_args" => RbConfig::CONFIG["configure_args"],
    }
end

# Takes a block as input
def run_benchmark(num_itrs_hint)
  times = []
  total_time = 0
  num_itrs = 0

  YJIT.reset_stats! if HAS_YJIT_STATS
  begin
    time = Benchmark.realtime { yield }
    num_itrs += 1

    # NOTE: we may want to avoid this as it could trigger GC?
    time_ms = (1000 * time).to_i
    puts "itr \##{num_itrs}: #{time_ms}ms"

    # NOTE: we may want to preallocate an array and avoid append
    # We internally save the time in seconds to avoid loss of precision
    times << time
    total_time += time
  end until num_itrs >= WARMUP_ITRS + MIN_BENCH_ITRS and total_time >= MIN_BENCH_TIME
  yjit_stats = HAS_YJIT_STATS ? YJIT.runtime_stats : nil

  out_data = {
    times: times,
    metadata: ruby_metadata.merge({
        warmup_itrs: WARMUP_ITRS,
        min_bench_itrs: MIN_BENCH_ITRS,
        min_bench_time: MIN_BENCH_TIME,
    }),
  }
  out_data[:yjit_stats] = YJIT.runtime_stats if HAS_YJIT_STATS
  File.open(OUT_JSON_PATH, "w") { |f| f.write(JSON.generate(out_data)) }
end
