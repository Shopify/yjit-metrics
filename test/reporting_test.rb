require_relative "test_helper"

class TestBasicReporting < Minitest::Test
    def setup
    end

    def test_load_multiple_real_data
        results = YJITMetrics::ResultSet.new
        results.add_for_config "no_jit", JSON.load(File.read "test/data/basic_benchmark_prod_ruby_no_jit_2021-07-13-084249.json")
        results.add_for_config "with_jit", JSON.load(File.read "test/data/basic_benchmark_prod_ruby_with_yjit_2021-07-13-084249.json")
        results.add_for_config "with_stats", JSON.load(File.read "test/data/basic_benchmark_yjit_stats_2021-07-13-084249.json")

        assert_equal [ "no_jit", "with_jit", "with_stats" ], results.available_configs.sort
        assert_equal [ "with_stats" ], results.configs_containing_yjit_stats
    end

    def test_creating_yjit_stats_multi_ruby_report
        results = YJITMetrics::ResultSet.new
        results.add_for_config "no_jit", JSON.load(File.read "test/data/basic_benchmark_prod_ruby_no_jit_2021-07-13-084249.json")
        results.add_for_config "with_yjit", JSON.load(File.read "test/data/basic_benchmark_prod_ruby_with_yjit_2021-07-13-084249.json")
        results.add_for_config "with_stats", JSON.load(File.read "test/data/basic_benchmark_yjit_stats_2021-07-13-084249.json")

        report = YJITMetrics::YJITStatsMultiRubyReport.new [ "no_jit", "with_yjit", "yjit_stats" ], results
        report.to_s
    end

    def test_calculation_with_synthetic_data
        results = YJITMetrics::ResultSet.new
        results.add_for_config "fake_ruby", JSON.load(File.read "test/data/synthetic_data.json")

        report = YJITMetrics::YJITStatsExitReport.new ["fake_ruby"], results
        report_text = report.to_s

        assert report_text.include?("getinstancevariable exit reasons: \n    (all relevant counters are zero)"),
            "Report should say that all getinstancevariable exit reasons are zero"
    end
end
