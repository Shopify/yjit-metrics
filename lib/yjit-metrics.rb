# General-purpose benchmark management routines

require 'fileutils'
require 'tempfile'
require 'json'
require 'csv'
require 'erb'

require_relative "./yjit-metrics/bench-results"
require_relative "./yjit-metrics/repo-management"

# Require all source files in yjit-metrics/report_types/*.rb
Dir.glob("yjit-metrics/report_types/*.rb", base: __dir__).each do |report_type_file|
    require_relative report_type_file
end

module YJITMetrics
    extend self # Make methods callable as YJITMetrics.method_name

    include YJITMetrics::RepoManagement

    HARNESS_PATH = File.expand_path(__dir__ + "/../metrics-harness")

    JSON_RUN_FIELDS = %i(times warmups yjit_stats peak_mem_bytes benchmark_metadata ruby_metadata)
    RunData = Struct.new(*JSON_RUN_FIELDS) do
        def times_ms
            self.times.map { |v| 1000.0 * v }
        end

        def warmups_ms
            self.warmups.map { |v| 1000.0 * v }
        end
    end

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

    def run_harness_script_from_string(script)
        tf = Tempfile.new("yjit-metrics-script")
        tf.write(script)
        tf.flush # Not flushing can result in successfully running an empty script

        script_output = nil
        harness_script_pid = nil
        worker_pid = nil

        # Passing -l to bash makes sure to load .bash_profile for chruby.
        IO.popen(["bash", "-l", tf.path], err: [:child, :out]) do |script_out_io|
            harness_script_pid = script_out_io.pid
            script_output = ""
            loop do
                begin
                    chunk = script_out_io.readpartial(1024)

                    # The harness will print the harness PID before doing anything else.
                    if (worker_pid.nil? && chunk.include?("HARNESS PID"))
                        if chunk =~ /HARNESS PID: (\d+) -/
                            worker_pid = $1.to_i
                        else
                            puts "Failed to read harness PID correctly from chunk: #{chunk.inspect}"
                        end
                    end

                    print chunk
                    script_output += chunk
                rescue EOFError
                    # Cool, all done.
                    break
                end
            end
        end

        return({
            failed: !$?.success?,
            exitstatus: $?.exitstatus,
            harness_script_pid: harness_script_pid,
            worker_pid: worker_pid,
            output: script_output
        })
    ensure
        if(tf)
            tf.close
            tf.unlink
        end
    end

    def os_type
        if RUBY_PLATFORM["darwin"]
            :mac
        elsif RUBY_PLATFORM["win"]
            :win
        else
            :linux
        end
    end

    def per_os_checks
        if os_type == :win
            puts "Windows is not supported or tested yet. Best of luck!"
            return
        end

        if os_type == :mac
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
                puts("You forgot to disable turbo: (note: sudo ./setup.sh will do this)")
                puts("  sudo sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo'")
                exit(-1)
            end
        end

        if !File.exist?('/sys/devices/system/cpu/intel_pstate/min_perf_pct')
            return
        end

        File.open('/sys/devices/system/cpu/intel_pstate/min_perf_pct', mode='r') do |file|
            if file.read.strip != '100'
                puts("You forgot to set the min perf percentage to 100: (note: sudo ./setup.sh will do this)")
                puts("  sudo sh -c 'echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct'")
                exit(-1)
            end
        end
    end

    def per_os_shell_prelude
        if os_type == :linux
            # On Linux, disable address space randomization for determinism unless YJIT_METRICS_USE_ASLR is specified
            (ENV["YJIT_METRICS_USE_ASLR"] ? [] : ["setarch", "x86_64", "-R"]) +
            # And pin the process to one given core to improve caching
            (ENV["YJIT_METRICS_NO_PIN"] ? [] : ["taskset", "-c", "11"])
        else
            []
        end
    end

    # Run the inner block given, watching for crash files showing up.
    # In some cases there may be multiple relevant files, so we return
    # a list.
    def with_crash_tracking
        os = os_type
        if os == :linux
            FileUtils.rm_f("core")
        elsif os == :mac
            crash_pattern = "#{ENV['HOME']}/Library/Logs/DiagnosticReports/ruby_*.crash"
            ruby_crash_files_before = Dir[crash_pattern].to_a
        end

        did_fail = false
        exc = nil

        begin
            did_fail = yield
        rescue
            did_fail = true
            puts "Exception inside crash tracker...\n#{$!.full_message}"
        ensure
            if os == :linux
                return ["core"] if File.exist?("core")
                return nil
            elsif os == :mac
                # Horrifying realisation: it takes a short time after the segfault for the crash file to be written.
                # Matching these up is really hard to do automatically, particularly when/if we're not sure if
                # they'll be showing up at all.
                sleep(1) if did_fail

                ruby_crash_files = Dir[crash_pattern].to_a
                # If any new ruby_* crash files have appeared, include them.
                return (ruby_crash_files - ruby_crash_files_before).sort
            end
        end
    end

    # The yjit-metrics harness returns its data as a simple hash for that benchmark:
    #
    #    {
    #       "times" => [ 2.3, 2.5, 2.7, 2.4, ...],  # The benchmark returns times in seconds, not milliseconds
    #       "benchmark_metadata" => {...},
    #       "ruby_metadata" => {...},
    #       "yjit_stats" => {...},  # Note: yjit_stats may be empty, but is present. It's a hash, not an array.
    #    }
    #
    # This method returns a RunData struct. Note that only a single yjit stats
    # hash is returned for all iterations combined, while times and warmups are
    # arrays with sizes equal to the number of 'real' and warmup iterations,
    # respectively.
    #
    # If on_error is specified it should be a proc that takes a hash. In case of
    # an exception or a failing status returned by the harness script,
    # that proc will be called with information about the error that occurred.
    # If on_error raises (or re-raises) an exception then the benchmark run will
    # stop. If no exception is raised, this method will collect no samples and
    # will return nil.
    def run_benchmark_path_with_runner(bench_name, script_path, output_path:".", ruby_opts: [], with_chruby: nil,
        warmup_itrs: 15, min_benchmark_itrs: 10, min_benchmark_time: 10.0, enable_core_dumps: false, on_error: nil)

        out_json_path = File.expand_path(File.join(output_path, 'temp.json'))
        FileUtils.rm_f(out_json_path) # No stale data please

        ruby_opts_section = ruby_opts.map { |s| '"' + s + '"' }.join(" ")
        pre_benchmark_code = enable_core_dumps ? "ulimit -c unlimited" : ""
        script_template = ERB.new File.read(__dir__ + "/../metrics-harness/run_harness.sh.erb")
        bench_script = script_template.result(binding) # Evaluate an Erb template with locals like warmup_itrs

        failed = false
        exc = nil

        # Do the benchmarking
        begin
            script_details = nil
            crash_files = with_crash_tracking do
                script_details = run_harness_script_from_string(bench_script)
                script_details[:failed]
            end
            crash_files ||= [] # Empty list is fine, nil is not
            failed = script_details[:failed]
            worker_pid = script_details[:worker_pid]
            script_output = script_details[:output]
            exit_status = script_details[:exitstatus]
        rescue
            failed = true
            exc = $!
        end

        if failed
            # Sometimes we'll get a Ruby exception. Sometimes the
            # harness gets the exception, so no exception has
            # happened in this process. If we don't have one,
            # we'll create an exception for on_error to raise.
            if exc.nil?
                exc = RuntimeError.new("Failure in benchmark test harness, exit status: #{exit_status.inspect}")
            end

            # What should go in here? What should the interface be? Many of these things will
            # be unavailable, depending what stage of the script got an error.
            on_error.call({
                exception: exc,
                crash_files: crash_files, # Empty unless a core/crash was dumped
                output: script_output,
                benchmark_name: bench_name,
                benchmark_path: script_path,
                ruby_opts: ruby_opts,
                with_chruby: with_chruby,
                json_file: out_json_path,
                worker_pid: worker_pid, # This is how we can locate the core dump for the process later
            })

            return nil
        end

        # Read the benchmark data
        single_bench_data = JSON.load(File.read out_json_path)
        obj = RunData.new *JSON_RUN_FIELDS.map { |field| single_bench_data[field.to_s] }
        obj.yjit_stats = nil if obj.yjit_stats.nil? || obj.yjit_stats.empty?

        # Add per-benchmark metadata from this script to the data returned from the harness.
        obj.benchmark_metadata.merge!({
            "benchmark_name" => bench_name,
            "chruby_version" => with_chruby,
            "ruby_opts" => ruby_opts
        })

        obj
    end

    # Run all the benchmarks and record execution times.
    # This method converts the benchmark_list to a set of benchmark names and paths.
    # It also combines results from multiple worker subprocesses.
    #
    # This method returns a benchmark data array of the following form:
    #
    #    {
    #       "times" => { "yaml-load" => [ 2.3, 2.5, 2.7, 2.4, ...], "psych" => [...] },
    #       "benchmark_metadata" => { "yaml-load" => {...}, "psych" => { ... }, },
    #       "ruby_metadata" => {...},
    #       "yjit_stats" => { "yaml-load" => {...}, ... }, # Note: yjit_stats may be empty, but is present
    #       "peak_mem_bytes" => { "yaml-load" => 2343423, "psych" => 112234, ... },
    #    }
    #
    # For timings, YJIT stats and benchmark metadata, we add a hash inside
    # each top-level key for each benchmark name, e.g.:
    #
    #    "times" => { "yaml-load" => [ 2.3, 2.5, 2.7, 2.4, ...] }
    #
    # If no valid data was successfully collected (e.g. a single benchmark was to run, but failed)
    # then this method will return nil.
    def run_benchmarks(benchmark_dir, out_path, ruby_opts: [], benchmark_list: [], with_chruby: nil,
                        enable_core_dumps: false, on_error: nil,
                        warmup_itrs: 15, min_benchmark_itrs: 10, min_benchmark_time: 10.0)
        bench_data = {}
        JSON_RUN_FIELDS.each { |f| bench_data[f.to_s] = {} }

        Dir.chdir(benchmark_dir) do
            # Get the list of benchmark files/directories matching name filters
            bench_files = Dir.children('benchmarks').sort
            legal_bench_names = (bench_files + bench_files.map { |name| name.delete_suffix(".rb") }).uniq
            benchmark_list.map! { |name| name.delete_suffix(".rb") }

            unknown_benchmarks = benchmark_list - legal_bench_names
            raise(RuntimeError.new("Unknown benchmarks: #{unknown_benchmarks.inspect}!")) if unknown_benchmarks.size > 0
            bench_files = benchmark_list if benchmark_list.size > 0

            raise "No testable benchmarks found!" if bench_files.empty?
            bench_files.each_with_index do |bench_name, idx|
                puts("Running benchmark \"#{bench_name}\" (#{idx+1}/#{bench_files.length})")

                # Path to the benchmark runner script
                script_path = File.join('benchmarks', bench_name)

                # Choose the first of these that exists
                real_script_path = [script_path, script_path + ".rb", script_path + "/benchmark.rb"].detect { |path| File.exist?(path) && !File.directory?(path) }
                raise "Could not find benchmark file starting from script path #{script_path.inspect}!" unless real_script_path
                script_path = real_script_path

                run_data = run_benchmark_path_with_runner(
                    bench_name, script_path,
                    output_path: out_path, ruby_opts: ruby_opts, with_chruby: with_chruby,
                    enable_core_dumps: enable_core_dumps, on_error: on_error,
                    warmup_itrs: warmup_itrs, min_benchmark_itrs: min_benchmark_itrs, min_benchmark_time: min_benchmark_time)

                unless run_data
                    # An error occurred. The error handler was specified and called,
                    # but didn't throw an exception.
                    # No usable data was collected for this benchmark and Ruby config,
                    # so we'll move on with our day.
                    next
                end

                # Return times and warmups in milliseconds, not seconds
                bench_data["times"][bench_name] = run_data.times_ms
                bench_data["warmups"][bench_name] = run_data.warmups_ms

                bench_data["yjit_stats"][bench_name] = [run_data.yjit_stats]
                bench_data["benchmark_metadata"][bench_name] = run_data.benchmark_metadata
                bench_data["peak_mem_bytes"][bench_name] = run_data.peak_mem_bytes

                # We don't save individual Ruby metadata for all benchmarks because it
                # should be identical for all of them -- we use the same Ruby
                # every time. Instead we save one copy of it, but we make sure
                # on each subsequent benchmark that it returned exactly the same
                # metadata about the Ruby version.
                bench_data["ruby_metadata"] = run_data.ruby_metadata if bench_data["ruby_metadata"].empty?
                if bench_data["ruby_metadata"] != run_data.ruby_metadata
                    puts "Ruby metadata 1: #{bench_data["ruby_metadata"].inspect}"
                    puts "Ruby metadata 2: #{run_data.ruby_metadata.inspect}"
                    raise "Ruby benchmark metadata should not change across a single set of benchmark runs!"
                end
            end
        end

        # With error handlers, it's possible that every benchmark had an error so there's no data to return.
        return nil if bench_data["times"].empty?

        return bench_data
    end
end
