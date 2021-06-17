# General-purpose benchmark management routines

require 'fileutils'
require 'tempfile'
require 'json'
require 'csv'

# TODO: re-add OS-specific args/prelude

HARNESS_PATH = File.expand_path(__dir__ + "/../metrics-harness")

# Checked system - error if the command fails
def check_call(command, verbose: false)
    puts(command)

    if verbose
        status = system(command, out: $stdout, err: :out)
    else
        status = system(command)
    end

    unless status
        puts "Command #{command.inspect} failed in directory #{Dir.pwd}"
        raise RuntimeError.new
    end
end

def check_output(command)
    output = IO.popen(command).read
    unless $?.success?
        puts "Command #{command.inspect} failed in directory #{Dir.pwd}"
        raise RuntimeError.new
    end
    output
end

def run_script_from_string(script)
    tf = Tempfile.new("yjit-metrics-script")
    tf.write(script)
    tf.flush

    status = system("bash", "-il", tf.path, out: :out, err: :err)

    unless status
        STDERR.puts "Script failed in directory #{Dir.pwd}"
        raise RuntimeError.new
    end
ensure
    if(tf)
        tf.close
        tf.unlink
    end
end

def per_os_checks
    return if RUBY_PLATFORM["darwin"]

    # Only available on intel systems
    if !File.exist?('/sys/devices/system/cpu/intel_pstate/no_turbo')
        return
    end

    File.open('/sys/devices/system/cpu/intel_pstate/no_turbo', mode='r') do |file|
        if file.read.strip != '1'
            puts("You forgot to disable turbo:")
            puts("  sudo sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'")
            exit(-1)
        end
    end

    if !File.exist?('/sys/devices/system/cpu/intel_pstate/min_perf_pct')
        return
    end

    File.open('/sys/devices/system/cpu/intel_pstate/min_perf_pct', mode='r') do |file|
        if file.read.strip != '100'
            puts("You forgot to set the min perf percentage to 100:")
            puts("  sudo sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'")
            exit(-1)
        end
    end
end

def per_os_ruby_opts
  if RUBY_PLATFORM["darwin"]
    []
  elsif RUBY_PLATFORM["win"]
    []
  else
    # On Linux, disable address space randomization for determinism
    ["setarch", "x86_64", "-R"] +
    # And pin the process to one given core to improve caching
    ["taskset", "-c", "11"]
  end
end

def mean(values)
    return values.sum(0.0) / values.size
end

def stddev(values)
    xbar = mean(values)
    diff_sqrs = values.map { |v| (v-xbar)*(v-xbar) }
    mean_sqr = diff_sqrs.sum(0.0) / values.length
    return Math.sqrt(mean_sqr)
end

def make_repo_with(path:, git_url:, git_branch:)
    unless File.exist?(path)
        check_call("git clone '#{git_url}' '#{path}'")
    end

    Dir.chdir(path) do
        check_call("git checkout #{git_branch}")
        check_call("git pull")

        # TODO: git clean?
    end
end

def make_ruby_repo_with(path:, git_url:, git_branch:, config_opts:, config_env: [], install_to:)
    make_repo_with(path: path, git_url: git_url, git_branch: git_branch)

    Dir.chdir(path) do
        config_opts += [ "--prefix=#{install_to}" ]

        unless File.exist?("./configure")
            check_call("./autogen.sh")
        end

        if !File.exist?("./config.status")
            should_configure = true
        else
            config_status_output = check_output("./config.status --conf").split(" ").sort
            desired_config = config_opts.sort
            if config_status_output != desired_config
                should_configure = true
                STDERR.puts "Stop and check: #{config_status_output.inspect} / #{desired_config.inspect}"
                raise
            end
        end

        if should_configure
            check_call("#{config_env.join(" ")} ./configure #{ config_opts.join(" ") }")
            check_call("make clean")
        end

        check_call("make")
        check_call("make install")
    end
end

# Run all the benchmarks and record execution times
def run_benchmarks(benchmark_dir, out_path, ruby_opts: [], benchmark_list: [], warmup_itrs: 15, with_chruby: nil)
    bench_data = { "times" => {}, "metadata" => {}, "yjit_stats" => {} }

    Dir.chdir(benchmark_dir) do
        # Get the list of benchmark files/directories matching name filters
        bench_files = Dir.children('benchmarks').sort
        unknown_benchmarks = benchmark_list - bench_files
        raise(RuntimeError.new("Unknown benchmarks: #{unknown_benchmarks.inspect}!")) if unknown_benchmarks.size > 0
        bench_files = benchmark_list if benchmark_list.size > 0

        bench_files.each_with_index do |entry, idx|
            bench_name = entry.gsub('.rb', '')

            puts("Running benchmark \"#{bench_name}\" (#{idx+1}/#{bench_files.length})")

            # Path to the benchmark runner script
            script_path = File.join('benchmarks', entry)

            if !script_path.end_with?('.rb')
                script_path = File.join(script_path, 'benchmark.rb')
            end

            json_path = File.expand_path(File.join(out_path, 'temp.json'))
            FileUtils.rm_f(json_path) # No stale data please

            chruby_section = with_chruby ? "chruby #{with_chruby}" : ""
            ruby_opts_section = ruby_opts.map { |s| '"' + s + '"' }.join(" ")
            bench_script = <<BENCH_SCRIPT
#!/bin/bash
# Shopify-specific workaround
if [[ -f /opt/dev/sh/chruby/chruby.sh ]]; then
  source /opt/dev/sh/chruby/chruby.sh
fi

set -e

#{chruby_section}

export OUT_JSON_PATH=#{json_path}
export WARMUP_ITRS=#{warmup_itrs}
export YJIT_STATS=1 # Only for YJIT Rubies compiled with RUBY_DEBUG

ruby -I#{HARNESS_PATH} #{per_os_ruby_opts.join(" ")} #{ruby_opts_section} #{script_path}
BENCH_SCRIPT

            # Do the benchmarking
            run_script_from_string(bench_script)

            # Read the benchmark data
            # Convert times to ms
            single_bench_data = JSON.load(File.read json_path)
            times = single_bench_data["times"].map { |v| 1000 * v.to_f }
            single_metadata = single_bench_data["metadata"]
            single_metadata.merge({
                "benchmark_name" => entry,
                "chruby_version" => with_chruby,
                "ruby_opts" => ruby_opts
            })
            bench_data["times"][bench_name] = times
            if single_bench_data["yjit_stats"] && !single_bench_data["yjit_stats"].empty?
                bench_data["yjit_stats"][bench_name] = single_bench_data["yjit_stats"]
            end
            bench_data["metadata"][bench_name] = single_bench_data["metadata"]
        end
    end

    return bench_data
end
