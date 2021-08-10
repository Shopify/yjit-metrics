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

    # This structure is returned by the benchmarking harness from a run.
    JSON_RUN_FIELDS = %i(times warmups yjit_stats peak_mem_bytes benchmark_metadata ruby_metadata)
    RunData = Struct.new(*JSON_RUN_FIELDS) do
        def times_ms
            self.times.map { |v| 1000.0 * v }
        end

        def warmups_ms
            self.warmups.map { |v| 1000.0 * v }
        end

        def to_json
            out = { "version": 2 } # Current version of the single-run data file format
            JSON_RUN_FIELDS.each { |f| out[f.to_s] = self.send(f) }
            out
        end

        def self.from_json(json)
            unless json["version"] == 2
                raise "This looks like out-of-date single-run data!"
            end

            RunData.new *JSON_RUN_FIELDS.map { |f| json[f.to_s] }
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

    def run_harness_script_from_string(script,
            local_popen: proc { |*args, **kwargs, &block| IO.popen(*args, **kwargs, &block) },
            crash_file_check: true,
            do_echo: true)
        run_info = {}

        os = os_type

        if crash_file_check
            if os == :linux
                FileUtils.rm_f("core")
            elsif os == :mac
                crash_pattern = "#{ENV['HOME']}/Library/Logs/DiagnosticReports/ruby_*.crash"
                ruby_crash_files_before = Dir[crash_pattern].to_a
            end
        end

        tf = Tempfile.new("yjit-metrics-script")
        tf.write(script)
        tf.flush # Not flushing can result in successfully running an empty script

        script_output = nil
        harness_script_pid = nil
        worker_pid = nil

        # We basically always want this to sync immediately to console or logfile.
        # If the library was run with nohup (or otherwise not connected to a tty)
        # that won't happen by default.
        $stdout.sync = true

        # Passing -l to bash makes sure to load .bash_profile for chruby.
        local_popen.call(["bash", "-l", tf.path], err: [:child, :out]) do |script_out_io|
            harness_script_pid = script_out_io.pid
            script_output = ""
            loop do
                begin
                    chunk = script_out_io.readpartial(1024)

                    # The harness will print the worker PID before doing anything else.
                    if (worker_pid.nil? && chunk.include?("HARNESS PID"))
                        if chunk =~ /HARNESS PID: (\d+) -/
                            worker_pid = $1.to_i
                        else
                            puts "Failed to read harness PID correctly from chunk: #{chunk.inspect}"
                        end
                    end

                    print chunk if do_echo
                    script_output += chunk
                rescue EOFError
                    # Cool, all done.
                    break
                end
            end
        end

        # This code and the ensure handler need to point to the same
        # status structure so that both can make changes (e.g. to crash_files).
        # We'd like this structure to be simple and serialisable -- it's
        # passed back from the framework, more or less intact.
        run_info.merge!({
            failed: !$?.success?,
            crash_files: [],
            exit_status: $?.exitstatus,
            harness_script_pid: harness_script_pid,
            worker_pid: worker_pid,
            output: script_output
        })

        return run_info
    ensure
        if(tf)
            tf.close
            tf.unlink
        end

        if crash_file_check
            if os == :linux
                run_info[:crash_files] = [ "core" ] if File.exist?("core")
            elsif os == :mac
                # Horrifying realisation: it takes a short time after the segfault for the crash file to be written.
                # Matching these up is really hard to do automatically, particularly when/if we're not sure if
                # they'll be showing up at all.
                sleep(1) if run_info[:failed]

                ruby_crash_files = Dir[crash_pattern].to_a
                # If any new ruby_* crash files have appeared, include them.
                run_info[:crash_files] = (ruby_crash_files - ruby_crash_files_before).sort
            end
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

    class BenchmarkList
        attr_reader :yjit_bench_path

        def initialize(name_list:, yjit_bench_path:)
            @name_list = name_list
            @yjit_bench_path = File.expand_path(yjit_bench_path)

            bench_names = Dir.glob("*", base: "#{@yjit_bench_path}/benchmarks")
            legal_bench_names = (bench_names + bench_names.map { |name| name.delete_suffix(".rb") }).uniq
            @name_list.map! { |name| name.delete_suffix(".rb") }

            unknown_benchmarks = name_list - legal_bench_names
            raise(RuntimeError.new("Unknown benchmarks: #{unknown_benchmarks.inspect}!")) if unknown_benchmarks.size > 0
            bench_names = @name_list if @name_list.size > 0
            raise "No testable benchmarks found!" if bench_names.empty? # This should presumably not happen after the "unknown" check

            @benchmark_script_by_name = {}
            bench_names.each do |bench_name|
                script_path = "#{@yjit_bench_path}/benchmarks/#{bench_name}"

                # Choose the first of these that exists
                real_script_path = [script_path, script_path + ".rb", script_path + "/benchmark.rb"].detect { |path| File.exist?(path) && !File.directory?(path) }
                raise "Could not find benchmark file starting from script path #{script_path.inspect}!" unless real_script_path
                @benchmark_script_by_name[bench_name] = real_script_path
            end
        end

        # For now, benchmark_info returns a Hash. At some point it may want to get fancier.
        def benchmark_info(name)
            raise "Querying unknown benchmark name #{name.inspect}!" unless @benchmark_script_by_name[name]
            {
                name: name,
                script_path: @benchmark_script_by_name[name],
            }
        end

        # If we call .map, we'll pretend to be an array of benchmark_info hashes
        def map
            @benchmark_script_by_name.keys.map do |name|
                yield benchmark_info(name)
            end
        end
    end

    # Eventually we'd like to do fancy things with interesting settings.
    # Before that, let's encapsulate the settings in a simple object so
    # we can pass them around easily.
    #
    # Harness Settings are about how to sample the benchmark repeatedly -
    # iteration counts, thresholds, etc.
    class HarnessSettings
        LEGAL_SETTINGS = [ :warmup_itrs, :min_benchmark_itrs, :min_benchmark_time ]

        def initialize(settings)
            illegal_keys = settings.keys - LEGAL_SETTINGS
            raise "Illegal settings given to HarnessSettings: #{illegal_keys.inspect}!" unless illegal_keys.empty?
            @settings = settings
        end

        def [](key)
            @settings[key]
        end

        def to_h
            @settings
        end
    end

    # Shell Settings encapsulate how we run Ruby and the appropriate shellscript
    # for each sampling run. That means which Ruby, which Ruby and shell options,
    # what env vars to set, whether core dumps are enabled, what to do on error and more.
    class ShellSettings
        LEGAL_SETTINGS = [ :ruby_opts, :chruby, :enable_core_dumps, :on_error ]

        def initialize(settings)
            illegal_keys = settings.keys - LEGAL_SETTINGS
            raise "Illegal settings given to ShellSettings: #{illegal_keys.inspect}!" unless illegal_keys.empty?
            @settings = settings
        end

        def [](key)
            @settings[key]
        end

        def to_h
            @settings
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
    def run_single_benchmark(benchmark_info, harness_settings:, shell_settings:,
        run_script: proc { |s| run_harness_script_from_string(s) })

        out_tempfile = Tempfile.new("yjit-metrics-single-run")

        env_vars = {
            OUT_JSON_PATH:  out_tempfile.path,
            WARMUP_ITRS:    harness_settings[:warmup_itrs],
            MIN_BENCH_ITRS: harness_settings[:min_benchmark_itrs],
            MIN_BENCH_TIME: harness_settings[:min_benchmark_time],
        }

        with_chruby = shell_settings[:chruby]

        script_template = ERB.new File.read(__dir__ + "/../metrics-harness/run_harness.sh.erb")
        # These are used in the ERB template
        template_settings = {
            pre_benchmark_code: (with_chruby ? "chruby #{with_chruby}" : "") +
                (shell_settings[:enable_core_dumps] ? "ulimit -c unlimited" : ""),
            env_var_exports: env_vars.map { |key, val| "export #{key}='#{val}'" }.join("\n"),
            ruby_opts: "-I#{HARNESS_PATH} " + shell_settings[:ruby_opts].map { |s| '"' + s + '"' }.join(" "),
            script_path: benchmark_info[:script_path],
        }
        bench_script = script_template.result(binding) # Evaluate an Erb template with template_settings

        # Do the benchmarking
        script_details = run_script.call(bench_script)

        if script_details[:failed]
            # We shouldn't normally get a Ruby exception in the parent process. Instead the harness
            # process fails and returns an exit status. We'll create an exception for the error
            # handler to raise if it decides this is a fatal error.
            exc = RuntimeError.new("Failure in benchmark test harness, exit status: #{script_details[:exit_status].inspect}")

            raise exc unless shell_settings[:on_error]

            # What should go in here? What should the interface be? Some things will
            # be unavailable, depending what stage of the script got an error.
            shell_settings[:on_error].call(script_details.merge({
                exception: exc,
                benchmark_name: benchmark_info[:name],
                benchmark_path: benchmark_info[:script_path],
                harness_settings: harness_settings.to_h,
                shell_settings: shell_settings.to_h,
            }))

            return nil
        end

        # Read the benchmark data
        json_string_data = File.read out_tempfile.path
        if json_string_data == ""
            # The tempfile exists, so no read error... But no data returned.
            raise "No error from benchmark, but no data was returned!"
        end
        single_bench_data = JSON.load(json_string_data)
        obj = RunData.new(*JSON_RUN_FIELDS.map { |field| single_bench_data[field.to_s] })
        obj.yjit_stats = nil if obj.yjit_stats.nil? || obj.yjit_stats.empty?

        # Add per-benchmark metadata from this script to the data returned from the harness.
        obj.benchmark_metadata.merge!({
            "benchmark_name" => benchmark_info[:name],
            "benchmark_path" => benchmark_info[:script_path],
        })

        obj
    ensure
        if out_tempfile
            out_tempfile.close
            out_tempfile.unlink
        end
    end

    # This method combines run_data objects from multiple benchmark runs.
    #
    # It returns a benchmark data array of the following form:
    #
    #    {
    #       "times" => { "yaml-load" => [[ 2.3, 2.5, 2.7, 2.4, ...],[...]] "psych" => [...] },
    #       "warmups" => { "yaml-load" => [[ 2.3, 2.5, 2.7, 2.4, ...],[...]] "psych" => [...] },
    #       "benchmark_metadata" => { "yaml-load" => {}, "psych" => { ... }, },
    #       "ruby_metadata" => {...},
    #       "yjit_stats" => { "yaml-load" => [{...}, {...}, ...] },
    #       "peak_mem_bytes" => { "yaml-load" => [2343423, 2349341, ...], "psych" => [112234, ...], ... },
    #    }
    #
    # For times, warmups, YJIT stats and benchmark metadata, that means there is a hash inside
    # each top-level key for each benchmark name, e.g.:
    #
    #    "times" => { "yaml-load" => [[ 2.3, 2.5, 2.7, 2.4, ...], [...], ...] }
    #
    # For times, warmups and YJIT stats that means the value of each hash value is an array.
    # For times and warmups, the top-level array is the runs, and the sub-arrays are iterations
    # in a single run. For YJIT stats, the top-level array is runs and the hash is the gathered
    # YJIT stats for that run.
    #
    # If no valid data was successfully collected (e.g. a single benchmark was to run, but failed)
    # then this method will return nil.
    def merge_benchmark_data(all_run_data)
        bench_data = { "version": 2 }
        JSON_RUN_FIELDS.each { |f| bench_data[f.to_s] = {} }

        all_run_data.each do |run_data|
            bench_name = run_data.benchmark_metadata["benchmark_name"]

            bench_data["times"][bench_name] ||= []
            bench_data["warmups"][bench_name] ||= []
            bench_data["yjit_stats"][bench_name] ||= []
            bench_data["peak_mem_bytes"][bench_name] ||= []

            # Return times and warmups in milliseconds, not seconds
            bench_data["times"][bench_name].push run_data.times_ms
            bench_data["warmups"][bench_name].push run_data.warmups_ms

            bench_data["yjit_stats"][bench_name].push [run_data.yjit_stats]
            bench_data["peak_mem_bytes"][bench_name].push run_data.peak_mem_bytes

            # Benchmark metadata should be unique per-benchmark. In other words,
            # we do *not* want to combine runs with different amounts of warmup,
            # iterations, etc, into the same dataset.
            bench_data["benchmark_metadata"][bench_name] ||= run_data.benchmark_metadata
            if bench_data["benchmark_metadata"][bench_name] != run_data.benchmark_metadata
                puts "#{bench_name} metadata 1: #{bench_data["benchmark_metadata"][bench_name].inspect}"
                puts "#{bench_name} metadata 2: #{run_data.benchmark_metadata.inspect}"
                puts "Benchmark metadata should not change for benchmark #{bench_name} in the same configuration!"
            end

            # We don't save individual Ruby metadata for all benchmarks because it
            # should be identical for all of them -- we use the same Ruby
            # every time. Instead we save one copy of it, but we make sure
            # on each subsequent benchmark that it returned exactly the same
            # metadata about the Ruby version.
            bench_data["ruby_metadata"] = run_data.ruby_metadata if bench_data["ruby_metadata"].empty?
            if bench_data["ruby_metadata"] != run_data.ruby_metadata
                puts "Ruby metadata 1: #{bench_data["ruby_metadata"].inspect}"
                puts "Ruby metadata 2: #{run_data.ruby_metadata.inspect}"
                raise "Ruby metadata should not change across a single set of benchmark runs in the same Ruby config!"
            end
        end

        # With error handlers it's possible that every benchmark had an error so there's no data to return.
        return nil if bench_data["times"].empty?

        return bench_data
    end
end
