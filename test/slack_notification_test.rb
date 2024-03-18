# frozen_string_literal: true

require "json"
require "rbconfig"
require "tempfile"

require_relative "test_helper"

# This is a high-level integration test to execute the continuous_reporting/slack_build_notifier.rb entrypoint
# and verify its behavior based on the calls it makes to the slack api.

# You can regenerate test data by running test/generate_slack_data.sh and then updating the DATA_GLOB constant below.

class SlackNotificationTest < Minitest::Test
  TEST_LIB = File.expand_path('lib', __dir__)
  JOB_NAME = "test-job"
  BUILD_URL = "https://build-url"
  SLACK_CHANNEL = "#yjit-benchmark-ci"
  SLACK_SCRIPT = "continuous_reporting/slack_build_notifier.rb"
  DATA_GLOB = "test/data/2024-03-18-203751*.json"
  IMAGE_PREFIX = "https://raw.githubusercontent.com/yjit-raw/yjit-reports/main/images"

  def notify(args: [], job_result: 'success')
    file = Tempfile.new('yjit-metrics-slack').tap(&:close)

    system(
      {
        'BUILD_URL' => BUILD_URL,
        'JOB_NAME' => JOB_NAME,
        'YJIT_METRICS_SLACK_DUMP' => file.path,
        'SLACK_OAUTH_TOKEN' => 'test-token',
      },
      RbConfig.ruby,
      "-I#{TEST_LIB}",
      "-rslack-ruby-client-report",
      SLACK_SCRIPT,
      "--properties=STATUS=#{job_result}",
      *args
    )

    {
      status: $?,
      report: JSON.parse(File.read(file.path), symbolize_names: true),
    }
  ensure
    file&.unlink
  end

  def test_success
    result = notify()

    assert_predicate(result[:status], :success?)

    assert_equal([:clients], result[:report].keys)

    clients = result[:report][:clients]
    assert_equal(1, clients.size)

    messages = clients.first[:messages]
    assert_equal(1, messages.size)

    message = messages.first
    assert_equal(SLACK_CHANNEL, message[:channel])

    summary = "#{JOB_NAME}: success"
    assert_equal(summary, message[:text])

    blocks = message[:blocks]
    assert_equal(2, blocks.size)
    assert_equal({type: "header", text: {type: "plain_text", text: summary}}, blocks[0])
    assert_equal("section", blocks[1][:type])
    assert_equal({type: "mrkdwn", text: "#{BUILD_URL}\n\n"}, blocks[1][:text])

    assert_equal("image", blocks[1][:accessory][:type])
    assert_equal("#{IMAGE_PREFIX}/build-success.png", blocks[1][:accessory][:image_url])
  end

  def test_failure
    result = notify(
      job_result: "fail",
      args: Dir.glob(DATA_GLOB),
    )

    assert_predicate(result[:status], :success?)

    assert_equal([:clients], result[:report].keys)

    clients = result[:report][:clients]
    assert_equal(1, clients.size)

    messages = clients.first[:messages]
    assert_equal(1, messages.size)

    message = messages.first
    assert_equal(SLACK_CHANNEL, message[:channel])

    summary = "#{JOB_NAME}: fail"
    assert_equal(summary, message[:text])

    blocks = message[:blocks]
    assert_equal(2, blocks.size)
    assert_equal({type: "header", text: {type: "plain_text", text: summary}}, blocks[0])
    assert_equal("section", blocks[1][:type])
    assert_equal("mrkdwn", blocks[1][:text][:type])

    assert_equal(<<~MSG, blocks[1][:text][:text])
      #{BUILD_URL}

      *`cycle_error`* (`arm_yjit_stats`)

      Details:

      *`cycle_error`*

      exit status 1 (`arm_yjit_stats`)
      ```
      ./benchmarks/cycle_error/benchmark.rb:24:in `block in <main>': Time to fail (RuntimeError)
      ```
    MSG

    assert_equal("image", blocks[1][:accessory][:type])
    assert_equal("#{IMAGE_PREFIX}/build-fail.png", blocks[1][:accessory][:image_url])
  end
end
