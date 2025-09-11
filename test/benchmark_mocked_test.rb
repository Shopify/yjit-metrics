require_relative "test_helper"

# For these tests we don't want to run the harness. We want to fake running the harness
# using a fake popen to avoid interacting with (e.g.) the contents of the ruby-bench repo.
class FakePopen
    def initialize(expected_args: nil, readpartial_results:, worker_pid: 12345, harness_script_pid: 54321, stderr: "")
        @expected_args = expected_args
        @readpartial_results = ["HARNESS PID: #{worker_pid} -\n"] + readpartial_results
        @worker_pid = worker_pid
        @harness_script_pid = harness_script_pid
        @stderr = stderr
    end

    def call(args, err:)
        assert_equal(@expected_args, args) if @expected_args

        err.write(@stderr)

        # We need to set $?, so we'll run a trivial script to say "success".
        # On error, we'll run another one that fails.
        system("true")

        # This object is both the IO object in popen's block and the object that's called.
        yield(self)
    end

    def pid
        @harness_script_pid
    end

    def readpartial(size)
        val = @readpartial_results.shift

        # We want $? set to "process got an error code"
        system("false") if val == :die

        # On :die or :eof, raise an EOFError
        raise(EOFError.new) if val == :eof || val == :die

        assert(false, "Not enough readpartial_results in FakePopen!") if val.nil?
        val
    end
end

class TestBenchmarkingWithMocking < Minitest::Test
    def setup
    end

    # "Basic success" test of the harness runner using a fake IO.popen() to impersonate a harness child process
    def test_harness_runner
        fake_popen = FakePopen.new readpartial_results: [ "chunk1\n", "chunk2\n", :eof ], stderr: "err1\nerr2\n"

        run_info = YJITMetrics.run_harness_script_from_string("fake script contents", local_popen: fake_popen, crash_file_check: false, do_echo: false)

        assert_equal false, run_info[:failed]
        assert_equal [], run_info[:crash_files]
        assert_equal 54321, run_info[:harness_script_pid]
        assert_equal 12345, run_info[:worker_pid]
        assert_equal "err1\nerr2\n", run_info[:stderr]
        assert run_info[:output].include?("chunk1"), "First chunk isn't in script output!"
        assert run_info[:output].include?("chunk2"), "Second chunk isn't in script output!"
    end

    def test_harness_runner_with_exception
        fake_popen = FakePopen.new readpartial_results: [ "chunk1\n", :die ], stderr: "err3"

        run_info = YJITMetrics.run_harness_script_from_string("fake script", local_popen: fake_popen, crash_file_check: false, do_echo: false)

        assert_equal true, run_info[:failed]
        assert_equal [], run_info[:crash_files] # We're raising an exception, but that shouldn't generate a new core file
        assert_equal 54321, run_info[:harness_script_pid] # PIDs should be passed even on exception
        assert_equal 12345, run_info[:worker_pid]
        assert_equal "err3", run_info[:stderr]
        assert run_info[:output].include?("chunk1"), "First chunk isn't in script output!"
    end

    # "Basic success" test using a fake script runner to impersonate a successful benchmark
    def test_single_benchmark
        test_data_dir = "#{__dir__}/data"

        # A script-runner expects to receive a bash script as a parameter,
        # and to return the details of that script's success or failure.
        # It's also supposed to write results to temp.json.
        fake_runner = proc do |script_contents|
            unless script_contents =~ /export OUT_JSON_PATH=(['"])(.*)\1$/
                raise "Couldn't find the OUT_JSON_PATH in the script contents!"
            end

            out_json_path = $2

            FileUtils.cp("#{test_data_dir}/synthetic_data.json", out_json_path)

            {}
        end

        hs = YJITMetrics::HarnessSettings.new({
            warmup_itrs: 15,
            min_benchmark_itrs: 10,
            min_benchmark_time: 10.0,
        })

        ss = YJITMetrics::ShellSettings.new({
            ruby: nil,
            ruby_opts: [ "--with-fake-jit" ],
            enable_core_dumps: false,
            on_error: nil,
        })

        result = YJITMetrics.run_single_benchmark(
            # Information about the ruby-bench benchmark
            { name: "single_bench", script_path: "/path/to/single_bench.rb" },
            harness_settings: hs,
            shell_settings: ss,
            run_script: fake_runner)

        assert_predicate result, :success?
        assert_equal 0, result.exit_status
    end

    # Test failure of a benchmark, as though the subprocess returned error
    def test_single_benchmark_failure
        fake_runner_details = {
            failed: true,
            exit_status: -1,
            crash_files: [],
            harness_script_pid: 12345,
            worker_pid: 54321,
            output: "Process failed!",
        }

        # A script-runner expects to receive a bash script as a parameter,
        # and to return the details of that script's success or failure.
        # It's also supposed to write results to temp.json.
        fake_runner = proc { |script_contents| fake_runner_details }

        on_err_proc = proc do |err_info|
            fake_runner_details.each do |key, val|
                assert_equal val, err_info[key], "On_errer callback should match runner fail info for field #{key}!"
            end
            assert err_info[:exception], "On_error handler should set up an exception to re-throw!"
            assert_equal "single_bench", err_info[:benchmark_name], "On_error callback should receive the correct benchmark name!"
            assert_equal "/path/to/single_bench.rb", err_info[:benchmark_path], "On_error callback should receive the correct benchmark path!"
            assert_equal [ "--with-fake-jit" ], err_info[:shell_settings][:ruby_opts], "On_error callback should receive the correct ruby_opts!"
            assert_equal "fakeruby-1.2.3", err_info[:shell_settings][:ruby], "On_error callback should receive the correct with_ruby!"
        end

        hs = YJITMetrics::HarnessSettings.new({
            warmup_itrs: 15,
            min_benchmark_itrs: 10,
            min_benchmark_time: 10.0,
        })

        ss = YJITMetrics::ShellSettings.new({
            ruby_opts: [ "--with-fake-jit" ],
            ruby: "fakeruby-1.2.3",
            enable_core_dumps: false,
            on_error: on_err_proc,
            # Missing: additional non-Ruby command-line params
        })

        result = YJITMetrics.run_single_benchmark(
            # Information about the ruby-bench benchmark
            { name: "single_bench", script_path: "/path/to/single_bench.rb" },
            harness_settings: hs,
            shell_settings: ss,
            run_script: fake_runner)

        refute_predicate result, :success?
        assert_equal(-1, result.exit_status)
    end

end
