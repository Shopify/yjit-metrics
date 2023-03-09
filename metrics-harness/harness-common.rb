# We should flush output indicating progress even if we're not hooked up to a tty (e.g. nohup).
# As a side effect, the HARNESS PID print will flush immediately.
STDOUT.sync = true

# This will be read from yjit-metrics.rb to track the PID later.
# The space-dash at the end is to make sure we got the whole thing
# rather than readpartial stopping midway.
print "HARNESS PID: #{Process.pid} -\n"

# Save the value of any environment variable whose name contains a string in this case-insensitive list.
# Note: this means you can store extra non-framework metadata about any run by setting an env var
# starting with YJIT_METRICS before running it.
IMPORTANT_ENV = [ "ruby", "gem", "bundle", "ld_preload", "path", "yjit_metrics" ]

YJIT_MODULE = defined?(YJIT) ? YJIT : (defined?(RubyVM::YJIT) ? RubyVM::YJIT : nil)

yjit_metrics_using_gemfile = false

srand(1337) # Matches value in yjit-bench harness. TODO: make configurable?

# Everything in ruby_metadata is supposed to be static for a single Ruby interpreter.
# It shouldn't include timestamps or other data that changes from run to run.
def ruby_metadata
  require "rbconfig"
  {
    "RUBY_VERSION" => RUBY_VERSION,
    "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
    "RUBY_ENGINE" => RUBY_ENGINE,
    "which ruby" => `which ruby`,
    "hostname" => `hostname`,
    "ec2 instance id" => `wget -q --timeout 1 --tries 2 -O - http://169.254.169.254/latest/meta-data/instance-id`,
    "ec2 instance type" => `wget -q --timeout 1 --tries 2 -O - http://169.254.169.254/latest/meta-data/instance-type`,
    "arch" => RbConfig::CONFIG["arch"],
    "uname -a" => `uname -a`,

    # Ruby compile-time settings: do we want to record more of them?
    "RbConfig configure_args" => RbConfig::CONFIG["configure_args"],
  }
end

# Specify a Gemfile and directory to use; install gems; do any extra per-benchmark setup.
# This varies from the yjit-bench harness method because it specifies one exact Bundler version.
def use_gemfile(extra_setup_cmd: nil)
  yjit_metrics_using_gemfile = true

  setup_cmds([ "bundle install --quiet", extra_setup_cmd].compact)

  # Need to be in the appropriate directory
  require "bundler/setup"
end

def setup_cmds(c)
  chruby_stanza = ""
  if ENV['RUBY_ROOT']
    ruby_name = ENV['RUBY_ROOT'].split("/")[-1]
    chruby_stanza = "chruby && chruby #{ruby_name}"
  end

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

  script = <<~SCRIPT
    set -e # Die on errors

    # If Shopify-specific devtools script exists on this computer, source it.
    [ -f /opt/dev/dev.sh ] && . /opt/dev/dev.sh

    #{chruby_stanza}

    #{c.join("\n")}
  SCRIPT

  puts "Running script...\n============\n#{script}\n============\n"

  require "tempfile"
  t = Tempfile.new("yjit-metrics-harness")
  begin
    t.write(script)
    t.close # Not closing/flushing your tempfile can mean successfully running an empty script
    system("bash -l #{t.path}") || raise("Error running setup_cmds! Failing!")
  ensure
    t.close
    t.unlink
  end
end

CMD_REPLACE = {
  "ruby" => RbConfig.ruby,
  "bundle" => "bundle _#{ENV['FORCE_BUNDLER_VERSION']}", # Should always be present in yjit-metrics
}

def run_cmd(*orig_cmd, silent: true)
  cmd = orig_cmd
  if cmd.respond_to?(:each)
    cmd = cmd.map { |item| CMD_REPLACE[item] || item }
  elsif cmd.respond_to?(:gsub)
    CMD_REPLACE.each do |k, v|
      cmd = cmd.gsub(k, v)
    end
  else
    raise "Unrecognised command type #{cmd.inspect}!"
  end

  system(*cmd) || raise("Error running command #{orig_cmd.inspect} via run_cmd: #{$!.inspect}")
end

def get_rss
  mem_rollup_file = "/proc/#{Process.pid}/smaps_rollup"
  if File.exist?(mem_rollup_file)
    # First, grab a line like "62796 kB". Checking the Linux kernel source, Rss will always be given in kB.
    rss_desc = File.read(mem_rollup_file).lines.detect { |line| line.start_with?("Rss") }.split(":", 2)[1].strip
    rss_desc.to_i
  else
    # Collect our own peak mem usage as soon as reasonable after finishing the last iteration.
    # This method is only accurate to kilobytes, but is nicely portable and doesn't require
    # any extra gems/dependencies.
    mem = `ps -o rss= -p #{Process.pid}`
    1024 * mem.to_i
  end
end

default_path = "results-#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}-#{Time.now.getgm.strftime('%F-%H%M%S')}.json"
OUT_JSON_PATH = File.expand_path(ENV.fetch('OUT_JSON_PATH', default_path))
RESULTS = {}

# Technically these are in different scopes. Nevertheless, let's not confuse
# them with normal returned data.
INTERNAL_KEYS = [:benchmark_metadata, :ruby_metadata, :env, :loaded_gems]

# Not normally called by benchmarks -- called by return_results and return_benchmark_metadata
def initial_benchmark_metadata
  unless RESULTS[:ruby_metadata]
    out_env_keys = ENV.keys.select { |k| IMPORTANT_ENV.any? { |s| k.downcase[s] } }

    # As a tempfile, this changes constantly but doesn't mean the benchmark results shouldn't be combined
    out_env_keys.delete "OUT_JSON_PATH"

    out_env = {}
    out_env_keys.each { |k| out_env[k] = ENV[k] }

    RESULTS[:ruby_metadata] = ruby_metadata
    RESULTS[:benchmark_metadata] = {
      env: out_env,
      loaded_gems: Gem.loaded_specs.map { |name, spec| [ name, spec.version.to_s ] },
    }
  end
end

def return_benchmark_metadata(mdata_hash)
  initial_benchmark_metadata
  bad_keys = mdata_hash.keys.map(&:to_sym) & INTERNAL_KEYS
  unless bad_keys.empty?
    raise "Can't return results with name(s) #{bad_keys.inspect}! Key(s) are used internally by yjit-metrics!"
  end

  RESULTS[:benchmark_metadata].merge!(mdata_hash)
end

def return_results(name, values)
  initial_benchmark_metadata
  if INTERNAL_KEYS.include?(name.to_sym)
    raise "Can't return results with name #{name.inspect}! That key is used internally by yjit-metrics!"
  end

  RESULTS[name] = values
end

at_exit do
  require 'json'
  File.open(OUT_JSON_PATH, "w") { |f| f.write(JSON.generate(RESULTS)) }
end
