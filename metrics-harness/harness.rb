# We should flush output indicating progress even if we're not hooked up to a tty (e.g. nohup).
# As a side effect, the HARNESS PID print will flush immediately.
STDOUT.sync = true

# This will be read from yjit-metrics.rb to track the PID later.
# The space-dash at the end is to make sure we got the whole thing
# rather than readpartial stopping midway.
print "HARNESS PID: #{Process.pid} -\n"

YJIT_MODULE = defined?(YJIT) ? YJIT : (defined?(RubyVM::YJIT) ? RubyVM::YJIT : nil)

# Warmup iterations
WARMUP_ITRS = ENV.fetch('WARMUP_ITRS', 0).to_i.nonzero? || if YJIT_MODULE&.enabled?
  50
else
  # Assume CRuby interpreter which doesn't need much warmup.
  5
end

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

# Ignore unnecessary env vars that match any of the above patterns.
IGNORABLE_ENV = %w[RBENV_ORIG_PATH GOPATH MANPATH INFOPATH]

srand(1337) # Matches value in yjit-bench harness. TODO: make configurable?

# Get string metadata about the running server (with "instance-type" returns "cX.metal"; Can fetch tags, etc).
INSTANCE_INFO = File.expand_path("./instance-info.sh", __dir__)
def instance_info(key, prefix: "meta-data/")
  `#{INSTANCE_INFO} "#{prefix}#{key}"`.strip
end

# Get information about the cpu (name, version).
def cpu_info
  if RUBY_PLATFORM.include?('linux')
    # Use a command where the output includes the word Graviton.
    json = JSON.parse(`sudo lshw -C CPU -json`.strip)
    json.detect { |j| !j["disabled"] }.then do |item|
      # Examples vary but may include:
      # version: "Intel(R) Xeon(R) Platinum 8488C", product: "Xeon"
      # version: "6.143.8", product: "Intel(R) Xeon(R) Platinum 8488C"
      # version: "AWS Graviton3" product: "ARMv8 (N/A)"
      # version: "AWS Graviton4" product: "(N/A)"
      if item["version"].include?(item["product"])
        item["version"]
      else
        [item["product"].delete_suffix('(N/A)').strip, item["version"]].reject(&:empty?).join(": ")
      end
    end
  elsif RUBY_PLATFORM.include?('darwin')
    # "Apple M3 Pro"
    `sysctl -n machdep.cpu.brand_string`.strip
  end
end

# Everything in ruby_metadata is supposed to be static for a single Ruby interpreter.
# It shouldn't include timestamps or other data that changes from run to run.
def ruby_metadata
    require "rbconfig"
    {
        "RUBY_VERSION" => RUBY_VERSION,
        "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
        "RUBY_PATCHLEVEL" => RUBY_PATCHLEVEL,
        "RUBY_ENGINE" => RUBY_ENGINE,
        "RUBY_ENGINE_VERSION" => RUBY_ENGINE_VERSION,
        "RUBY_PLATFORM" => RUBY_PLATFORM,
        "RUBY_REVISION" => RUBY_REVISION,
        "which ruby" => `which ruby`,
        "hostname" => `hostname`,
        "cpu info" => cpu_info,
        "ec2 instance id" => instance_info("instance-id"),
        "ec2 instance type" => instance_info("instance-type"),
        "arch" => RbConfig::CONFIG["arch"],
        "uname -a" => `uname -a`,

        # Ruby compile-time settings: do we want to record more of them?
        "RbConfig configure_args" => RbConfig::CONFIG["configure_args"],
        "RbConfig CC_VERSION_MESSAGE" => RbConfig::CONFIG["CC_VERSION_MESSAGE"],
    }
end

# Specify a Gemfile and directory to use; install gems; do any extra per-benchmark setup.
# This varies from the yjit-bench harness method because it specifies one exact Bundler version.
def use_gemfile(extra_setup_cmd: nil)
  setup_cmds([ "bundle install --quiet", extra_setup_cmd].compact)

  # Need to be in the appropriate directory
  require "bundler/setup"
end

def setup_cmds(c)
  env_bundler = ENV['FORCE_BUNDLER_VERSION']
  bundler_cmd = "bundle"
  if env_bundler # Should always be true in yjit-metrics
    gem "bundler", env_bundler # Make sure requiring bundler/setup gets the right one
    bundler_cmd = "bundle _#{env_bundler}_"
  end

  c = c.map do |cmd|
    if cmd["bundle"]
      cmd.gsub("bundle", bundler_cmd)
    else
      "#{bundler_cmd} exec #{cmd}"
    end
  end

  c.each do |cmd|
    puts "Running: #{cmd}"
    system(cmd) || raise("Error running setup_cmds! Failing!")
  end
end

def realtime
  r0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - r0
end

def run_benchmark(num_itrs_hint, &block)
  times = []
  total_time = 0
  num_itrs = 0

  # Note: this harness records *one* set of YJIT stats for all iterations
  # combined, including warmups. That's a good thing for our specific use
  # case, but would be awful for many other use cases.
  YJIT_MODULE&.reset_stats!
  begin
    time = realtime(&block)
    num_itrs += 1

    time_ms = (1000 * time).to_i
    print "itr \#", num_itrs, ": ", time_ms, "ms", "\n" # Minimize string allocations to reduce GC

    # NOTE: we may want to preallocate an array and avoid append
    # We internally save the time in seconds to avoid loss of precision
    times << time
    total_time += time
  end until num_itrs >= WARMUP_ITRS + MIN_BENCH_ITRS and total_time >= MIN_BENCH_TIME

  mem_rollup_file = "/proc/#{Process.pid}/smaps_rollup"
  if File.exist?(mem_rollup_file)
    # First, grab a line like "62796 kB". Checking the Linux kernel source, Rss will always be in kB.
    rss_desc = File.read(mem_rollup_file).lines.detect { |line| line.start_with?("Rss") }.split(":", 2)[1].strip
    peak_mem_bytes = 1024 * rss_desc.to_i
  else
    # Collect our own peak mem usage as soon as reasonable after finishing the last iteration.
    # This method is only accurate to kilobytes, but is nicely portable and doesn't require
    # any extra gems/dependencies.
    mem = `ps -o rss= -p #{Process.pid}`
    peak_mem_bytes = 1024 * mem.to_i
  end

  yjit_stats = YJIT_MODULE&.runtime_stats

  out_env_keys = ENV.keys.select { |k| IMPORTANT_ENV.any? { |s| k.downcase[s] } }
  out_env_keys -= IGNORABLE_ENV

  # As a tempfile, this changes constantly but doesn't mean the benchmark results shouldn't be combined
  out_env_keys -= ["OUT_JSON_PATH"]

  out_env = {}
  out_env_keys.each { |k| out_env[k] = ENV[k] }

  warmup_times = times[0...WARMUP_ITRS]
  warmed_times = times[WARMUP_ITRS..-1]

  # Require additional modules *after* collecting YJIT stats
  # to avoid irrelevant changes to the stats (invalidation counts, etc).
  require 'json'

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

  out_data[:yjit_stats] = yjit_stats
  File.open(OUT_JSON_PATH, "w") { |f| f.write(JSON.generate(out_data)) }
end
