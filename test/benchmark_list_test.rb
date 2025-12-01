# frozen_string_literal: true

require_relative "test_helper"

class BenchmarkListTest < Minitest::Test
  FAKE_RUBY_BENCH_DIR = File.expand_path('fake-ruby-bench', __dir__)

  def setup
    @yjit_bench_path = FAKE_RUBY_BENCH_DIR
  end

  def test_initialization_with_valid_benchmarks
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['pass', 'fail'],
      yjit_bench_path: @yjit_bench_path
    )

    assert_equal @yjit_bench_path, benchmark_list.yjit_bench_path
  end

  def test_initialization_with_rb_extension
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['pass.rb', 'fail.rb'],
      yjit_bench_path: @yjit_bench_path
    )

    names = benchmark_list.map { |info| info[:name] }
    assert_equal ['pass', 'fail'], names
  end

  def test_initialization_with_unknown_benchmarks
    error = assert_raises(RuntimeError) do
      YJITMetrics::BenchmarkList.new(
        name_list: ['nonexistent_benchmark'],
        yjit_bench_path: @yjit_bench_path
      )
    end

    assert_match(/Unknown benchmarks:/, error.message)
    assert_match(/nonexistent_benchmark/, error.message)
  end

  def test_initialization_with_mixed_valid_and_invalid
    error = assert_raises(RuntimeError) do
      YJITMetrics::BenchmarkList.new(
        name_list: ['pass', 'nonexistent'],
        yjit_bench_path: @yjit_bench_path
      )
    end

    assert_match(/Unknown benchmarks:/, error.message)
    assert_match(/nonexistent/, error.message)
  end

  def test_benchmark_info_returns_correct_structure
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['pass'],
      yjit_bench_path: @yjit_bench_path
    )

    info = benchmark_list.benchmark_info('pass')

    assert_equal 'pass', info[:name]
    assert_equal "#{@yjit_bench_path}/benchmarks/pass.rb", info[:script_path]
  end

  def test_benchmark_info_with_directory_benchmark
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['cycle_error'],
      yjit_bench_path: @yjit_bench_path
    )

    info = benchmark_list.benchmark_info('cycle_error')

    assert_equal 'cycle_error', info[:name]
    assert_equal "#{@yjit_bench_path}/benchmarks/cycle_error/benchmark.rb", info[:script_path]
  end

  def test_benchmark_info_with_unknown_name
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['pass'],
      yjit_bench_path: @yjit_bench_path
    )

    error = assert_raises(RuntimeError) do
      benchmark_list.benchmark_info('nonexistent')
    end

    assert_match(/Querying unknown benchmark name/, error.message)
  end

  def test_map_yields_benchmark_info
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['pass', 'fail'],
      yjit_bench_path: @yjit_bench_path
    )

    names = benchmark_list.map { |info| info[:name] }
    assert_equal ['pass', 'fail'], names

    benchmark_list.map do |info|
      assert_kind_of Hash, info
      assert info.key?(:name)
      assert info.key?(:script_path)
    end
  end

  def test_expands_yjit_bench_path
    relative_path = 'test/fake-ruby-bench'
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['pass'],
      yjit_bench_path: relative_path
    )

    assert_equal File.expand_path(relative_path), benchmark_list.yjit_bench_path
    refute_equal relative_path, benchmark_list.yjit_bench_path
  end

  def test_empty_name_list_finds_all_benchmarks
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: [],
      yjit_bench_path: @yjit_bench_path
    )

    benchmarks = benchmark_list.to_a

    benchmark_names = benchmarks.map { |b| b[:name] }.sort
    assert_equal 3, benchmark_names.size
    assert_equal ['cycle_error', 'fail', 'pass'], benchmark_names
  end

  def test_script_path_points_to_existing_file
    benchmark_list = YJITMetrics::BenchmarkList.new(
      name_list: ['pass', 'cycle_error'],
      yjit_bench_path: @yjit_bench_path
    )

    benchmark_list.to_a.each do |info|
      assert File.exist?(info[:script_path]), "Script path #{info[:script_path]} should exist"
      refute File.directory?(info[:script_path]), "Script path #{info[:script_path]} should not be a directory"
    end
  end
end
