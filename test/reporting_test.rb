require_relative "test_helper"

class TestMeme < Minitest::Test
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
end
