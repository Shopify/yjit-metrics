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
  build_status: proc do |properties, opts|
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
          "text": "#{properties["JOB_NAME"]}: #{properties["STATUS"]}",
        }
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "#{properties["BUILD_URL"]}\n\n#{opts[:summary]}"
        },
        "accessory": {
          "type": "image",
          "image_url": IMAGES[img][:url],
          "alt_text": IMAGES[img][:alt],
        },
      }
    ]
  end,

  smoke_test: proc do |properties, opts|
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
          "text": "#{properties["JOB_NAME"]}: #{properties["STATUS"]}",
        }
      },
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "*URL:* #{properties["BUILD_URL"]}\n*RUBY:* #{properties["RUBY"]}\n*YJIT-BENCH:* #{properties["YJIT_BENCH"]}\n*YJIT-METRICS:* #{properties["YJIT_METRICS"]}"
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
  "JOB_NAME" => ENV["JOB_NAME"],
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

TO_NOTIFY = to_notify

def template_substitute(tmpl_name, prop, opts)
  tmpl_name = tmpl_name.to_sym
  unless TEMPLATES.has_key?(tmpl_name)
    raise "Can't find template #{tmpl_name.inspect}! Known: #{TEMPLATES.keys.inspect}"
  end
  TEMPLATES[tmpl_name].call(prop, opts)
end

def send_message(tmpl_name, prop, opts)
  block_msg = template_substitute(tmpl_name, prop, opts)

  TO_NOTIFY.each do |channel|
    slack_client.chat_postMessage channel: channel, text: "#{prop["JOB_NAME"]}: #{prop["STATUS"]}", blocks: block_msg
  end
end

# Use Slack "mrkdwn" formatting.
# https://api.slack.com/reference/surfaces/formatting
def summary(files)
  return if files.empty?

  results = files.map { |f| JSON.parse(File.read(f)) }

  by_failure = results.each_with_object({}) do |result, h|
    result["benchmark_failures"]&.each do |name, arr|
      arr.each do |info|
        ((h[name] ||= {})[info.values_at("exit_status", "summary")] ||= []) << result["ruby_config_name"]
      end
    end
  end

  # results could be a list of empty hashes so test by_failure.
  return "All benchmarks completed successfully." if by_failure.empty?

  q = ->(s) { "`#{s}`" }

  lines = []

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

send_message(template, properties, {summary: summary(ARGV)})
