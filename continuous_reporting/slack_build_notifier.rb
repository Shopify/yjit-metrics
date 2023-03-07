#!/usr/bin/env ruby -w
# frozen_string_literal: true

require 'slack-ruby-client'

SLACK_TOKEN = ENV["SLACK_OAUTH_TOKEN"]

unless SLACK_TOKEN
  raise "Can't run slack_build_notifier.rb without a Slack token in env var SLACK_OAUTH_TOKEN!"
end

Slack.configure do |config|
  config.token = ENV["SLACK_OAUTH_TOKEN"]
end

def slack_client
  @slack_client ||= Slack::Web::Client.new
end

# Die if we can't connect to Slack
slack_client.auth_test

require "optparse"

def slack_notification_targets(spec)
  spec.split(/;|\s|,/).map do |str|
    if str[0] == "#"
      str
    elsif str.include?("@")
      # Look up email
      raise "Can't do this! This requires risky permissions for the Slack App!"
      users = slack_client.users_lookupByEmail(email: str)
      raise "Looking up users: #{users.inspect}"
    else
      # Slack Member ID? Return it.
      str
    end
  end
end

IMAGES = {
  cute_cat: {
    url: "https://pbs.twimg.com/profile_images/625633822235693056/lNGUneLX_400x400.jpg",
    alt_text: "Cute cat",
  },
}

to_notify = ["#yjit-benchmark-ci"]
image_name = :cute_cat

OptionParser.new do |opts|
  opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

  opts.on("--channels CHAN", "Channels to notify, including channel names, email addresses, Slack Member IDs") do |chan|
    to_notify = slack_notification_targets(chan)
  end

  opts.on("--image NAME", "Image name to go with message: success, fail, question") do |name|
    raise "Could not find image: #{name.inspect}!" unless IMAGES[image_name]
    image_name = name.to_sym
  end

end.parse!

if ARGV.size != 1
  raise "Expected one arg, instead got #{ARGV.inspect}!"
end

BUILD_URL = ENV['BUILD_URL']

TO_NOTIFY = to_notify
MESSAGE = ARGV[0]
IMAGE_URL = IMAGES[image_name][:url]
IMAGE_ALT = IMAGES[image_name][:alt_text]

def send_message
  block_msg = [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": MESSAGE,
      }
    },
    {
			"type": "section",
			"text": {
				"type": "mrkdwn",
				"text": "*URL:*\n#{BUILD_URL}"
			},
			"accessory": {
				"type": "image",
				"image_url": IMAGE_URL,
				"alt_text": IMAGE_ALT,
			},
		}
  ]

  TO_NOTIFY.each do |channel|
    STDERR.puts "Send #{MESSAGE.inspect} to #{channel.inspect}"
    slack_client.chat_postMessage channel: channel, text: MESSAGE, blocks: block_msg
  end
end

send_message
