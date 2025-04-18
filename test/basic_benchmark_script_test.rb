# frozen_string_literal: true

require_relative "test_helper"

require "rbconfig"

# This is a high-level integration test to execute the main ./basic_benchmark.rb entrypoint
# and verify its behavior based on the data in the resulting output files.

class BasicBenchmarkScriptTest < Minitest::Test
  PLATFORM = YJITMetrics::PLATFORM
  SCRIPT = File.expand_path('../basic_benchmark.rb', __dir__)
  FAKE_YJIT_BENCH_DIR = File.expand_path('fake-yjit-bench', __dir__)

  def setup
    @script = SCRIPT
    @output = Dir.mktmpdir('fake-yjit-bench-ouput')
  end

  def teardown
    FileUtils.rm_rf(@output)
  end

  def env
    {
      'YJIT_BENCH_DIR' => FAKE_YJIT_BENCH_DIR,
      'FAKE_YJIT_BENCH_OUTPUT' => @output,
    }
  end

  def output_data
    @output_data ||= Dir.glob("#{@output}/*.json").map do |file|
      JSON.parse(File.read(file))
    end
  end

  def run_script(args: [], configs: [])
    system(
      env,
      RbConfig.ruby,
      @script,
      '--skip-git-updates',
      '--output', @output,
      '--configs', configs.map { |x| "#{PLATFORM}_#{x}" }.join(','),
      *args,
    )

    $?
  end

  def test_basic
    result = run_script(
      configs: %w[yjit_stats prod_ruby_no_jit],
      args: %w[--warmup-itrs=0 --min-bench-time=0.0 --min-bench-itrs=1 --on-errors=report --max-retries=1]
    )

    refute_predicate result, :success?

    output_data.each do |data|
      assert_equal 2, data['version']

      times = data['times']
      assert_equal 1, times['pass'].size
      assert times['pass'].first.first > 0
      assert_equal 1, times['cycle_error'].size
      assert times['cycle_error'].first.first > 0

      assert_equal [0], data['failures_before_success']['pass']
      assert_equal [1], data['failures_before_success']['cycle_error']

      failures = data['benchmark_failures']
      assert_equal ['cycle_error', 'fail'], failures.keys.sort
      assert_equal 1, failures['cycle_error'].size
      assert_equal 1, failures['cycle_error'].first['exit_status']

      assert_match(
        %r{cycle_error/benchmark\.rb.+Time to fail},
        failures['cycle_error'].first['summary']
      )
    end
  end
end
