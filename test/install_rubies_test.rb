# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"
require "json"

class InstallRubiesTest < Minitest::Test
  SCRIPT = File.expand_path("../continuous_reporting/install_rubies.rb", __dir__)

  def setup
    @temp_dir = Dir.mktmpdir("install_rubies_test")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_validates_timestamp_format
    bench_params = { "ts" => "invalid-timestamp" }
    bench_params_file = write_bench_params(bench_params)

    output, status = run_script(bench_params_file: bench_params_file, dry_run: true)

    refute status.success?, "Expected script to fail on invalid timestamp"
    assert_match(/Bad format for given timestamp/, output)
  end

  def test_accepts_valid_timestamp_format
    bench_params = { "ts" => "2025-01-15-120000" }
    bench_params_file = write_bench_params(bench_params)

    output, status = run_script(bench_params_file: bench_params_file, dry_run: true)

    assert status.success?, "Expected script to succeed with valid timestamp: #{output}"
    assert_match(/BENCHMARK_DATE=20250115/, output)
  end

  def test_defaults_benchmark_date_to_today
    output, status = run_script(dry_run: true)

    assert status.success?, "Expected script to succeed: #{output}"
    today = Time.now.strftime("%Y%m%d")
    assert_match(/BENCHMARK_DATE=#{today}/, output)
  end

  def test_parses_cruby_override_from_bench_params
    bench_params = {
      "ts" => "2025-01-15-120000",
      "cruby_repo" => "https://github.com/test/ruby.git",
      "cruby_sha" => "abc123"
    }
    bench_params_file = write_bench_params(bench_params)

    output, status = run_script(bench_params_file: bench_params_file, dry_run: true)

    assert status.success?, "Expected script to succeed: #{output}"
    assert_match(/git_url.*test\/ruby\.git/, output)
    assert_match(/git_branch.*abc123/, output)
  end

  private

  def write_bench_params(data)
    file = File.join(@temp_dir, "bench_params.json")
    File.write(file, JSON.generate(data))
    file
  end

  def run_script(bench_params_file: nil, dry_run: false)
    env = {}
    env["BENCH_PARAMS"] = bench_params_file if bench_params_file

    config_arg = dry_run ? "#{YJITMetrics::PLATFORM}_test_config" : nil

    cmd = [
      RbConfig.ruby,
      "-rbundler/setup",
      "-e",
      dry_run_wrapper(SCRIPT, config_arg),
    ]

    output = IO.popen(env, cmd, err: [:child, :out]) { |io| io.read }
    [output, $?]
  end

  def dry_run_wrapper(script_path, config_arg)
    argv_setup = config_arg ? "ARGV.replace(['--configs=#{config_arg}'])" : "ARGV.clear"
    <<~RUBY
      #{argv_setup}

      module MetricsApp
        module Rubies
          def self.install_all!(*args)
            puts "DRY_RUN: install_all! called with: \#{args.inspect}"
          end

          def self.ruby(config)
            "/fake/path/to/ruby"
          end
        end
      end

      load #{script_path.inspect}
    RUBY
  end
end
