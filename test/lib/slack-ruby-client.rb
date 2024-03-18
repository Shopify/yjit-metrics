# frozen_string_literal: true

# This is a mock of the slack-ruby-client gem to facilitate integration testing.

module Slack
  class Config
    attr_accessor :token
  end

  def self.config
    @config ||= Config.new
  end

  def self.configure
    yield(config)
  end

  @clients = []

  def self.clients
    @clients
  end

  def self.report
    {
      clients: clients.map do |client|
        {
          messages: client.messages,
        }
      end
    }
  end

  module Web
    class Client
      attr_reader :messages

      def initialize
        Slack.clients << self
        @messages = []
      end

      def auth_test
        return if Slack.config.token == "test-token"

        raise "Should only be used from test suite"
      end

      def chat_postMessage(channel:, text:, blocks:)
        messages << {
          channel: channel,
          text: text,
          blocks: blocks,
        }
      end
    end
  end
end
