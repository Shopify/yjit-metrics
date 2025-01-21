#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'slack-ruby-client'

Slack.configure do |config|
  config.token = ENV.fetch("SLACK_OAUTH_TOKEN") do
    file = ENV.fetch("SLACK_TOKEN_FILE") do
      raise "Can't run slack_build_notifier.rb without SLACK_OAUTH_TOKEN or SLACK_TOKEN_FILE!"
    end
    File.read(file).strip
  end
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
      raise "Can't look up emails! Doing so requires risky permissions for the Slack App!"
      users = slack_client.users_lookupByEmail(email: str)
      raise "Looking up users: #{users.inspect}"
    else
      # Slack Member ID? Return it.
      str
    end
  end
end

IMAGES = {
  success: {
    url: "https://raw.githubusercontent.com/yjit-raw/yjit-reports/main/images/build-success.png",
    alt: "Large green check and the words 'Build Success, Because I am a Good Server'",
  },
  fail: {
    url: "https://raw.githubusercontent.com/yjit-raw/yjit-reports/main/images/build-fail.png",
    alt: "Large red X and the words 'Build Failed, All Your Fault I Assume'",
  },
  cat: {
    url: "https://pbs.twimg.com/profile_images/625633822235693056/lNGUneLX_400x400.jpg",
    alt: "Cute cat",
  },
}

def slack_message_blocks(title, body, img)
  # Convert actual markdown links of `[text](url)` to slack links `<url|text>`.
  body = body.gsub(/\[([^\]]+)\]\(([^)]+)\)/, '<\2|\1>')

  [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": title,
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": body.to_s,
      },
      "accessory": {
        "type": "image",
        "image_url": IMAGES[img][:url],
        "alt_text": IMAGES[img][:alt],
      },
    }
  ]
end

img = :cat
to_notify = ENV.fetch("SLACK_CHANNEL", "#yjit-benchmark-ci").split(",")
title = "Howdy!"

OptionParser.new do |opts|
  opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

  opts.on("--channels CHAN", "Channels to notify, including channel names, email addresses, Slack Member IDs") do |chan|
    to_notify = slack_notification_targets(chan)
  end

  opts.on("--image CODE", "Use image by name") do |arg|
    img = arg.to_sym
    raise("No such image: #{img.inspect}!") unless IMAGES.has_key?(img)
  end

  opts.on("--title TITLE", "Set message title") do |arg|
    title = arg
  end
end.parse!

TO_NOTIFY = to_notify

def send_message(title, body, img)
  block_msg = slack_message_blocks(title, body, img)

  TO_NOTIFY.each do |channel|
    slack_client.chat_postMessage channel: channel, text: title, blocks: block_msg
  end
end

# Use Slack "mrkdwn" formatting.
# https://api.slack.com/reference/surfaces/formatting
def body(files)
  lines = []

  lines << STDIN.read if files.delete("-")

  return lines.join("") if files.empty?

  results = files.map { |f| JSON.parse(File.read(f)) }

  by_failure = results.each_with_object({}) do |result, h|
    result["benchmark_failures"]&.each do |name, arr|
      arr.each do |info|
        ((h[name] ||= {})[info.values_at("exit_status", "summary")] ||= []) << result["ruby_config_name"]
      end
    end
  end

  # results could be a list of empty hashes so test by_failure.
  return "No benchmark errors." if by_failure.empty?

  q = ->(s) { "`#{s}`" }

  lines << "" if !lines.empty?

  # Line for each failed benchmark name with configs.
  lines += by_failure.map do |name, failures|
    "*#{q[name]}* (#{failures.values.flatten.sort.map(&q).join(", ")})"
  end

  lines << "\nDetails:\n"

  lines += by_failure.map do |(name, results)|
    [
      "*#{q[name]}*\n",
      results.map do |(exit_status, summary), configs|
        "exit status #{exit_status} (#{configs.sort.map(&q).join(", ")})\n```\n#{summary}\n```\n"
      end
    ]
  end

  lines.flatten.join("\n")
rescue StandardError => error
  "Error building slack message: #{error.class}: #{error.message}"
end

send_message(title, body(ARGV), img)
