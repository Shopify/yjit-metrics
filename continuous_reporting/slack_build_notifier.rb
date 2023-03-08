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

TEMPLATES = {
  build_failed: [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "PROP_MESSAGE",
      }
    },
    {
			"type": "section",
			"text": {
				"type": "mrkdwn",
				"text": "*URL:*\nPROP_BUILD_URL"
			},
			"accessory": {
				"type": "image",
				"image_url": "PROP_IMAGE_URL",
				"alt_text": "PROP_IMAGE_ALT",
			},
		}
  ]

}

to_notify = ["#yjit-benchmark-ci"]
properties = {
  "BUILD_URL" => ENV["BUILD_URL"],
  "IMAGE_URL" => "https://pbs.twimg.com/profile_images/625633822235693056/lNGUneLX_400x400.jpg",
  "IMAGE_ALT" => "Cute cat",
}
template = :build_failed

OptionParser.new do |opts|
  opts.banner = "Usage: basic_benchmark.rb [options] [<benchmark names>]"

  opts.on("--channels CHAN", "Channels to notify, including channel names, email addresses, Slack Member IDs") do |chan|
    to_notify = slack_notification_targets(chan)
  end

  opts.on("--properties PROP", "Set one or more string properties, e.g. '--properties title=FAIL,image=cute_cat'") do |properties|
    properties.split(",").each do |prop_assign|
      prop, val = properties.split("=", 2)
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

def template_substitute(block_struct, prop)
  case block_struct
  when String
    block_struct.gsub /PROP_([_A-Za-z0-9]+)/ do |prop_str|
      prop_name = prop_str.delete_prefix("PROP_")
      raise("Cannot find property: #{prop_str.inspect}/#{prop_name.inspect} in #{block_struct.inspect}!") unless prop.has_key?(prop_name)
      prop[prop_name]
    end
  when Symbol
    # No change
    block_struct
  when Array
    block_struct.map { |elt| template_substitute(elt, prop) }
  when Hash
    out = {}
    block_struct.each do |k, v|
      new_k = template_substitute(k, prop)
      new_v = template_substitute(v, prop)
      out[new_k] = new_v
    end
    out
  else
    raise "Template error: can't do template substitution on #{block_struct.inspect}!"
  end
end

def send_message(tmpl_name, prop)
  block_msg = template_substitute(TEMPLATES[tmpl_name], prop)

  TO_NOTIFY.each do |channel|
    slack_client.chat_postMessage channel: channel, text: prop["MESSAGE"], blocks: block_msg
  end
end

send_message(template, properties)
