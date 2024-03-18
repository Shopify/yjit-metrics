# frozen_string_literal: true

require "json"

require_relative "slack-ruby-client"

at_exit do
  ENV['YJIT_METRICS_SLACK_DUMP'].tap do |file|
    raise 'YJIT_METRICS_SLACK_DUMP env var not set' unless file

    File.write(file, JSON.generate(Slack.report))
  end
end
