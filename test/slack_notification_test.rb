# frozen_string_literal: true

require "json"
require "rbconfig"
require "tempfile"

require_relative "test_helper"

# This is a high-level integration test to execute the continuous_reporting/slack_build_notifier.rb entrypoint
# and verify its behavior based on the calls it makes to the slack api.

# You can regenerate test data by running test/generate_slack_data.sh.

class SlackNotificationTest < Minitest::Test
  TEST_LIB = File.expand_path('lib', __dir__)
  SLACK_CHANNEL = "#yjit-benchmark-ci"
  SLACK_SCRIPT = "continuous_reporting/slack_build_notifier.rb"
  DATA_GLOB = "test/data/slack/*.json"
  IMAGE_PREFIX = "https://raw.githubusercontent.com/yjit-raw/yjit-reports/main/images"

  class TestNotifier < YJITMetrics::Notifier
    def notify!
      file = Tempfile.new('yjit-metrics-slack').tap(&:close)
      token_file = Tempfile.new('slack-token').tap { |f| f.puts('test-token'); f.close }

      @env = {
        'YJIT_METRICS_SLACK_DUMP' => file.path,
        # 'SLACK_OAUTH_TOKEN' => 'test-token',
        'SLACK_TOKEN_FILE' => token_file.path,
        'RUBYOPT' => "-I#{TEST_LIB} -rslack-ruby-client-report",
      }

      super

      {
        status:,
        report: JSON.parse(File.read(file.path), symbolize_names: true),
      }
    ensure
      file&.unlink
    end
  end

  def notify(...)
    TestNotifier.new(...).notify!
  end

  def test_success
    summary = "nothing, really"
    result = notify(title: summary, image: :success)

    assert_slack_message(result, title: summary, image: "#{IMAGE_PREFIX}/build-success.png", body: "")
  end

  def test_failure
    summary = "benchmark failure"
    result = notify(title: summary, body: "stdin", image: :fail, args: Dir.glob(DATA_GLOB))

    assert_slack_message(result, title: summary, image: "#{IMAGE_PREFIX}/build-fail.png", body: <<~MSG)
      stdin

      *`cycle_error`* (`arm_prod_ruby_no_jit`, `arm_yjit_stats`)

      Details:

      *`cycle_error`*

      exit status 1 (`arm_prod_ruby_no_jit`, `arm_yjit_stats`)
      ```
      ./benchmarks/cycle_error/benchmark.rb:24:in `block in <main>': Time to fail (RuntimeError)
      ```
    MSG
  end

  def test_stdin
    summary = "Howdy!"
    result = notify(args: ["-"], body: "hello\nthere\n")

    assert_slack_message(result, title: summary, body: "hello\nthere\n", image: %r{https://\S+\.\w+})
  end

  def test_notify_error
    notifier = TestNotifier.new
    error = RuntimeError.new("something bad")
    error.set_backtrace([
      "elsewhere",
      "#{File.expand_path(__FILE__)}:5",
      "#{__dir__}/oops.rb:4",
      "#{__FILE__}:3",
    ])

    result = notifier.error(error).notify!

    summary = "RuntimeError: something bad"
    expected_body = <<~BODY
      ```
      - test/slack_notification_test.rb:5
      - test/oops.rb:4
      ```
    BODY

    assert_slack_message(result, title: summary, body: expected_body, image:  "#{IMAGE_PREFIX}/build-fail.png")
  end

  def test_notify_error_with_no_app_backtrace
    notifier = TestNotifier.new
    error = RuntimeError.new("something bad")
    error.set_backtrace([
      "elsewhere:1",
      "someplace:2",
      "another:3",
    ])

    result = notifier.error(error).notify!

    summary = "RuntimeError: something bad"
    expected_body = <<~BODY
      ```
      - elsewhere:1
      - someplace:2
      ```
    BODY

    assert_slack_message(result, title: summary, body: expected_body, image:  "#{IMAGE_PREFIX}/build-fail.png")
  end

  private

  def assert_slack_message(result, title:, body:, image:)
    assert_predicate(result[:status], :success?)

    assert_equal([:clients], result[:report].keys)

    clients = result[:report][:clients]
    assert_equal(1, clients.size)

    messages = clients.first[:messages]
    assert_equal(1, messages.size)

    message = messages.first
    assert_equal(SLACK_CHANNEL, message[:channel])

    assert_equal(title, message[:text])

    blocks = message[:blocks]
    assert_equal(2, blocks.size)
    assert_equal({type: "header", text: {type: "plain_text", text: title}}, blocks[0])
    assert_equal("section", blocks[1][:type])
    assert_equal("mrkdwn", blocks[1][:text][:type])

    assert_equal(body, blocks[1][:text][:text])

    assert_equal("image", blocks[1][:accessory][:type])
    assert_match(image, blocks[1][:accessory][:image_url])
  end
end
