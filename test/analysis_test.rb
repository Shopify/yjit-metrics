# frozen_string_literal: true

require "json"

require_relative "test_helper"

class AnalysisTest < Minitest::Test
  def test_ratio_in_yjit_double_drop
    # x86 railsbench 2024-09
    data = [
      99.69702407821114,
      99.69675919763544,
      99.80913411348729,
      99.80914070978066,
      99.8091196007074 ,
      99.80913165470788,
      99.6968184612434 , # 6
      99.69688050079795,
      99.69680638396541,
      99.69706713598048,
      99.69708500436587,
      99.69703337407694,
      99.48061463450416,
      99.48046943102433,
      99.48042116102302,
      99.4804711422886 ,
      99.48070716367374,
      99.48076661383709,
      99.48046622584835,
      99.48041897011268,
      99.48049201506213,
      99.48055223720182,
      99.48077768142517,
      99.48057686407698,
      99.48052248520104,
      99.48071826142501,
      99.48048653514832,
      99.48043501965125,
    ]

    assert_nil(ratio_in_yjit(data[0..5])[:regression])

    assert_equal("dropped from 99.81 to 99.70", ratio_in_yjit(data[0..6])[:regression])

    result = ratio_in_yjit(data)
    assert_equal("dropped from 99.81 to 99.48", result[:regression])
    assert_equal(
      [[99.7, 2], [99.81, 4], [99.7, 6], [99.48, 16]],
      result[:streaks],
    )
    assert_equal(99.81, result[:highest_streak_value])
    assert_equal([99.48, 16], result[:longest_streak])
  end

  def test_ratio_in_yjit_partial_recovery
    # x86 setivar_object 2025-01-01 - 2025-01-16
    data = [
      80.27678632430916,
      80.27679472575525,
      80.27678612938003,
      80.27678612938003,
      80.27679398502444,
      80.27678566155014,
      80.27678566155014,
      80.2767857785076,
      80.09313275306948, # 8
      79.90611966548313, # 9
      80.0932565733893,  # 10
      80.0932565733893,
      79.52159598537179,
    ]

    assert_nil(ratio_in_yjit(data[0..7])[:regression])

    assert_equal("dropped from 80.28 to 80.09", ratio_in_yjit(data[0..8])[:regression])
    assert_equal("dropped from 80.28 to 79.91", ratio_in_yjit(data[0..9])[:regression])
    assert_equal("dropped from 80.28 to 80.09", ratio_in_yjit(data[0..10])[:regression])

    result = ratio_in_yjit(data)
    assert_equal("dropped from 80.28 to 79.52", result[:regression])

    assert_equal(
      [[80.28, 8], [80.09, 1], [79.91, 1], [80.09, 2], [79.52, 1]],
      result[:streaks],
    )

    assert_equal(80.28, result[:highest_streak_value])
    assert_equal([80.28, 8], result[:longest_streak])
  end

  def test_ratio_in_yjit_no_streaks
    # x86 hexapdf 2025-01-01 - 2025-01-16
    data = [
      97.95467331975628,
      98.96788160765978,
      98.0063627126548,
      97.78843531296532,
      98.67933071337653,
      97.10413079155224,
      97.74498458826407,
      97.84358463126871,
      98.25253693934724,
      97.52501950636031,
      97.4763495529748,
      97.44065940965542,
      97.9821999376502,
    ]

    result = ratio_in_yjit(data)
    assert_nil(result[:regression])
    assert_nil(result[:highest_streak_value])
    assert_nil(result[:longest_streak])
  end

  def test_regression_notification
    data = {
      :yjit_stats => {
        "x86_64_yjit_stats" => [
          {
            "yjit_stats" => {
              "none" => [[{"ratio_in_yjit" => 97.123}]],
              "some" => [[{"ratio_in_yjit" => 89.123}]],
            },
          },
          {
            "yjit_stats" => {
              "none" => [[{"ratio_in_yjit" => 98.123}]],
              "some" => [[{"ratio_in_yjit" => 89.123}]],
            },
          },
          {
            "yjit_stats" => {
              "none" => [[{"ratio_in_yjit" => 99.123}]],
              "some" => [[{"ratio_in_yjit" => 88.123}]],
            },
          },
        ]
      }
    }
    data[:yjit_stats]["aarch64_yjit_stats"] = data[:yjit_stats]["x86_64_yjit_stats"]
    report = YJITMetrics::Analysis.report_from_data(data)

    assert_equal(
      <<~MSG.strip,
        ratio_in_yjit aarch64_yjit_stats
        - `some` regression: dropped from 89.12 to 88.12
        ratio_in_yjit x86_64_yjit_stats
        - `some` regression: dropped from 89.12 to 88.12
        #{YJITMetrics::Analysis::REPORT_LINK}
      MSG
      report.regression_notification,
    )
  end

  private

  def check_one(name, data)
    YJITMetrics::Analysis.const_get(name).new.check_one(data)
  end

  def ratio_in_yjit(data)
    check_one(:RatioInYJIT, data)
  end
end
