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
  build_success: {
    url: "https://raw.githubusercontent.com/yjit-raw/yjit-reports/main/images/build-success.png",
    alt: "Large green check and the words 'Build Success, Because I am a Good Server'",
  },
  build_fail: {
    url: "https://raw.githubusercontent.com/yjit-raw/yjit-reports/main/images/build-fail.png",
    alt: "Large red X and the words 'Build Failed, All Your Fault I Assume'",
  },
  cute_cat: {
    url: "https://pbs.twimg.com/profile_images/625633822235693056/lNGUneLX_400x400.jpg",
    alt: "Cute cat",
  },
}

TEMPLATES = {
  build_status: proc do |properties|
    img = properties["IMAGE"].to_sym
    raise("No such image: #{img.inspect}!") unless IMAGES.has_key?(img)
    [
      {
        "type": "header",
        "text": {
          "type": "plain_text",
          "text": properties["MESSAGE"],
        }
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "*URL:*\n#{properties["BUILD_URL"]}"
        },
        "accessory": {
          "type": "image",
          "image_url": IMAGES[img][:url],
          "alt_text": IMAGES[img][:alt],
        },
      }
    ]
  end,

  smoke_test: proc do |properties|
    if properties["IMAGE"]
      img = properties["IMAGE"].to_sym
    elsif properties["STATUS"] == "success"
      img = :build_success
    elsif properties["STATUS"] == "fail"
      img = :build_fail
    else
      img = :cute_cat
    end
    raise("No such image: #{img.inspect}!") unless IMAGES.has_key?(img)
    [
      {
        "type": "header",
        "text": {
          "type": "plain_text",
          "text": properties["MESSAGE"],
        }
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "*URL:* #{properties["BUILD_URL"]}\n*RUBY:* #{properties["RUBY"]}\n*YJIT-BENCH:* #{properties["YJIT_BENCH"]}\n*YJIT-METRICS:* #{properties["YJIT_METRICS"]}\n*STATUS:* #{properties["STATUS"]}"
        },
        "accessory": {
          "type": "image",
          "image_url": IMAGES[img][:url],
          "alt_text": IMAGES[img][:alt],
        },
      }
    ]
  end,

}

to_notify = ["#yjit-benchmark-ci"]
properties = {
  "BUILD_URL" => ENV["BUILD_URL"],
}
template = :build_status

OptionParser.new do |opts|
  opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

  opts.on("--channels CHAN", "Channels to notify, including channel names, email addresses, Slack Member IDs") do |chan|
    to_notify = slack_notification_targets(chan)
  end

  opts.on("--properties PROP", "Set one or more string properties, e.g. '--properties TITLE=Fail,IMAGE=cute_cat'") do |properties_str|
    properties_str.split(",").each do |prop_assign|
      prop, val = prop_assign.split("=", 2)
      properties[prop] = val
    end
  end

  opts.on("--template TEMPLATE", "Set the name of the template to use") do |template_name|
    template = template_name.to_sym
    raise "No such template: #{template_name.inspect}! Known: #{TEMPLATES.keys.inspect}" unless TEMPLATES[template]
  end

end.parse!

if ARGV.size != 1
  raise "Expected one arg, instead got #{ARGV.inspect}!"
end

TO_NOTIFY = to_notify
properties["MESSAGE"] = ARGV[0]

def template_substitute(tmpl_name, prop)
  tmpl_name = tmpl_name.to_sym
  unless TEMPLATES.has_key?(tmpl_name)
    raise "Can't find template #{tmpl_name.inspect}! Known: #{TEMPLATES.keys.inspect}"
  end
  TEMPLATES[tmpl_name].call(prop)
end

def send_message(tmpl_name, prop)
  block_msg = template_substitute(tmpl_name, prop)

  TO_NOTIFY.each do |channel|
    slack_client.chat_postMessage channel: channel, text: prop["MESSAGE"], blocks: block_msg
  end
end

send_message(template, properties)
