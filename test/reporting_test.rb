require_relative "test_helper"

class TestBasicReporting < Minitest::Test
    def setup
    end

    def test_load_multiple_real_data
        results = YJITMetrics::ResultSet.new
        results.add_for_config "no_jit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_no_jit.json")
        results.add_for_config "with_jit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_with_yjit.json")
        results.add_for_config "yjit_stats", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_yjit_stats.json")

        assert_equal [ "no_jit", "with_jit", "yjit_stats" ], results.available_configs.sort
        assert_equal [ "yjit_stats" ], results.configs_containing_full_yjit_stats
    end

    def test_creating_per_bench_report
        results = YJITMetrics::ResultSet.new
        results.add_for_config "no_jit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_no_jit.json")
        results.add_for_config "with_yjit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_with_yjit.json")
        results.add_for_config "yjit_stats", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_yjit_stats.json")

        report = YJITMetrics::PerBenchRubyComparison.new [ "no_jit", "with_yjit", "yjit_stats" ], results
        report.to_s
    end

    def test_creating_yjit_stats_multi_ruby_report
        results = YJITMetrics::ResultSet.new
        results.add_for_config "prod_ruby_no_jit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_no_jit.json")
        results.add_for_config "prod_ruby_with_yjit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_with_yjit.json")
        results.add_for_config "yjit_stats", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_yjit_stats.json")

        report = YJITMetrics::YJITStatsMultiRubyReport.new [ "prod_ruby_no_jit", "prod_ruby_with_yjit", "yjit_stats" ], results
        report.to_s
    end

    def test_creating_yjit_stats_exit_report
        results = YJITMetrics::ResultSet.new
        results.add_for_config "yjit_stats", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_yjit_stats.json")

        report = YJITMetrics::YJITStatsExitReport.new [ "yjit_stats" ], results
        report.to_s
    end

    # VMIL report is basically historical at this point, and should probably be archived or removed
#    def test_creating_vmil_report
#        results = YJITMetrics::ResultSet.new
#        results.add_for_config "no_jit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_no_jit.json")
#        results.add_for_config "with_yjit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_with_yjit.json")
#        results.add_for_config "with_mjit", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_prod_ruby_with_mjit.json")
#        results.add_for_config "with_stats", JSON.load(File.read "test/data/2021-09-13-100043_basic_benchmark_yjit_stats.json")
#
#        report = YJITMetrics::VMILReport.new [ "no_jit", "with_yjit", "with_mjit", "with_stats" ], results
#        report.to_s
#    end
end
