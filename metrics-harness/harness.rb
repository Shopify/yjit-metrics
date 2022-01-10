# We should flush output indicating progress even if we're not hooked up to a tty (e.g. nohup).
# As a side effect, the HARNESS PID print will flush immediately.
STDOUT.sync = true

# This will be read from yjit-metrics.rb to track the PID later.
# The space-dash at the end is to make sure we got the whole thing
# rather than readpartial stopping midway.
print "HARNESS PID: #{Process.pid} -\n"

require 'benchmark'
require 'json'
require 'rbconfig'

# Warmup iterations
WARMUP_ITRS = ENV.fetch('WARMUP_ITRS', 15).to_i

# Minimum number of benchmarking iterations
MIN_BENCH_ITRS = ENV.fetch('MIN_BENCH_ITRS', 10).to_i

# Minimum benchmarking time in seconds
MIN_BENCH_TIME = ENV.fetch('MIN_BENCH_TIME', 10).to_f

TIMESTAMP = Time.now.getgm

default_path = "results-#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}-#{TIMESTAMP.strftime('%F-%H%M%S')}.json"
OUT_JSON_PATH = File.expand_path(ENV.fetch('OUT_JSON_PATH', default_path))

# Save the value of any environment variable whose name contains a string in this case-insensitive list.
# Note: this means you can store extra non-framework metadata about any run by setting an env var
# starting with YJIT_METRICS before running it.
IMPORTANT_ENV = [ "ruby", "gem", "bundle", "ld_preload", "path", "yjit_metrics" ]

YJIT_MODULE = defined?(YJIT) ? YJIT : (defined?(RubyVM::YJIT) ? RubyVM::YJIT : nil)

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

# Specify a Gemfile and directory to use; install gems; do any extra per-benchmark setup.
# This varies from the yjit-bench harness method because it specifies one exact Bundler version.
def use_gemfile(extra_setup_cmd: nil)
  chruby_stanza = ""
  if ENV['RUBY_ROOT']
    ruby_name = ENV['RUBY_ROOT'].split("/")[-1]
    chruby_stanza = "chruby && chruby #{ruby_name} && "
  end

  # Source Shopify-located chruby if it exists to make sure this works in Shopify Mac dev tools.
  # Use bash -l to propagate non-Shopify-style chruby config.
  cmd = "/bin/bash -l -c '[ -f /opt/dev/dev.sh ] && . /opt/dev/dev.sh; #{chruby_stanza}bundle install'"
  if extra_setup_cmd
    cmd += " && #{extra_setup_cmd}"
  end
  puts "Command: #{cmd}"
  success = system(cmd)
  unless success
    raise "Couldn't set up benchmark in #{Dir.pwd.inspect}!"
  end

  # Need to be in the appropriate directory
  require "bundler/setup"
end

# Takes a block as input
def run_benchmark(num_itrs_hint)
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

    # NOTE: we may want to preallocate an array and avoid append
    # We internally save the time in seconds to avoid loss of precision
    times << time
    total_time += time
  end until num_itrs >= WARMUP_ITRS + MIN_BENCH_ITRS and total_time >= MIN_BENCH_TIME

  # Collect our own peak mem usage as soon as reasonable after finishing the last iteration.
  # This method is only accurate to kilobytes, but is nicely portable to Mac and Linux
  # and doesn't require any extra gems/dependencies.
  mem = `ps -o rss= -p #{Process.pid}`
  peak_mem_bytes = 1024 * mem.to_i

  yjit_stats = YJIT_MODULE&.runtime_stats

  out_env_keys = ENV.keys.select { |k| IMPORTANT_ENV.any? { |s| k.downcase[s] } }

  # As a tempfile, this changes constantly but doesn't mean the benchmark results shouldn't be combined
  out_env_keys -= ["OUT_JSON_PATH"]

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
        env: out_env,
        loaded_gems: Gem.loaded_specs.map { |name, spec| [ name, spec.version.to_s ] },
    },
    ruby_metadata: ruby_metadata,
    peak_mem_bytes: peak_mem_bytes,
  }
  mean = warmed_times.sum / warmed_times.size
  stddev = Math.sqrt(warmed_times.map { |t| (t - mean) ** 2.0 }.sum / warmed_times.size)
  rel_stddev_pct = stddev / mean * 100.0
  puts "Non-warmup iteration mean time: #{"%.2f ms" % (mean * 1000.0)} +/- #{"%.2f%%" % rel_stddev_pct}"

  out_data[:yjit_stats] = YJIT_MODULE&.runtime_stats
  File.open(OUT_JSON_PATH, "w") { |f| f.write(JSON.generate(out_data)) }
end
