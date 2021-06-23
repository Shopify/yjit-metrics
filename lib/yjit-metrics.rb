# General-purpose benchmark management routines

require 'fileutils'
require 'tempfile'
require 'json'
require 'csv'

module YJITMetrics
    extend self # Make methods callable as YJITMetrics.method_name

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
        tf.flush # No flush can result in successfully running an empty script

        # Passing -il to bash makes sure to load .bashrc/.bash_profile
        # for chruby.
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
        if RUBY_PLATFORM["darwin"]
            puts "Mac results are considered less stable for this benchmarking harness."
            puts "Please assume you'll need more runs and more time for similar final quality."
            return
        end

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

    def per_os_shell_prelude
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

    def clone_repo_with(path:, git_url:, git_branch:)
        unless File.exist?(path)
            check_call("git clone '#{git_url}' '#{path}'")
        end

        Dir.chdir(path) do
            check_call("git checkout #{git_branch}")
            check_call("git pull")

            # TODO: git clean?
        end
    end

    def clone_ruby_repo_with(path:, git_url:, git_branch:, config_opts:, config_env: [], install_to:)
        clone_repo_with(path: path, git_url: git_url, git_branch: git_branch)

        Dir.chdir(path) do
            config_opts += [ "--prefix=#{install_to}" ]

            unless File.exist?("./configure")
                check_call("./autogen.sh")
            end

            if !File.exist?("./config.status")
                should_configure = true
            else
                # Right now this config check is brittle - if you give it a config_env containing quotes, for
                # instance, it will tend to believe it needs to reconfigure. We cut out single-quotes
                # because they've caused trouble, but a full fix might need to understand bash quoting.
                config_status_output = check_output("./config.status --conf").gsub("'", "").split(" ").sort
                desired_config = config_opts.sort + config_env
                if config_status_output != desired_config
                    puts "Configuration is wrong, reconfiguring..."
                    puts "Desired: #{desired_config.inspect}"
                    puts "Current: #{config_status_output.inspect}"
                    should_configure = true
                end
            end

            if should_configure
                check_call("#{config_env.join(" ")} ./configure #{ config_opts.join(" ") }")
                check_call("make clean")
            end

            check_call("make -j16 install")
        end
    end

    # Run all the benchmarks and record execution times
    def run_benchmarks(benchmark_dir, out_path, ruby_opts: [], benchmark_list: [], warmup_itrs: 15, with_chruby: nil)
        bench_data = { "times" => {}, "benchmark_metadata" => {}, "ruby_metadata" => {}, "yjit_stats" => {} }

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
export YJIT_STATS=1 # Have YJIT Rubies compiled with RUBY_DEBUG collect statistics

#{per_os_shell_prelude.join(" ")} ruby -I#{HARNESS_PATH} #{ruby_opts_section} #{script_path}
BENCH_SCRIPT

                # Do the benchmarking
                run_script_from_string(bench_script)

                # Read the benchmark data
                single_bench_data = JSON.load(File.read json_path)

                # Convert times to ms
                times = single_bench_data["times"].map { |v| 1000 * v.to_f }

                single_metadata = single_bench_data["benchmark_metadata"]

                # Add per-benchmark metadata from this script to the data returned from the harness.
                single_metadata.merge({
                    "benchmark_name" => entry,
                    "chruby_version" => with_chruby,
                    "ruby_opts" => ruby_opts
                })

                # Each benchmark returns its data as a simple hash for that benchmark:
                #
                #    "times" => [ 2.3, 2.5, 2.7, 2.4, ...]
                #
                # For timings, YJIT stats and benchmark metadata, we add a hash inside
                # each top-level key for each benchmark name, e.g.:
                #
                #    "times" => { "yaml-load" => [ 2.3, 2.5, 2.7, 2.4, ...] }
                #
                # For Ruby metadata we don't save it for all benchmarks because it
                # should be identical for all of them -- we use the same Ruby
                # every time. Instead we save one copy of it, but we make sure
                # on each subsequent benchmark that it returned exactly the same
                # metadata about the Ruby version.
                bench_data["times"][bench_name] = times
                if single_bench_data["yjit_stats"] && !single_bench_data["yjit_stats"].empty?
                    bench_data["yjit_stats"][bench_name] = single_bench_data["yjit_stats"]
                end
                bench_data["benchmark_metadata"][bench_name] = single_metadata
                bench_data["ruby_metadata"] = single_bench_data["ruby_metadata"] if bench_data["ruby_metadata"].empty?
                if bench_data["ruby_metadata"] != single_bench_data["ruby_metadata"]
                    puts "Ruby metadata 1: #{bench_data["ruby_metadata"].inspect}"
                    puts "Ruby metadata 2: #{single_bench_data["ruby_metadata"].inspect}"
                    raise "Ruby benchmark metadata should not change across a single set of benchmark runs!"
                end
            end
        end

        return bench_data
    end
end
