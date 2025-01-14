# frozen_string_literal: true

# Send notification via slack.

module YJITMetrics
  class Notifier
    attr_accessor :body, :title, :image, :args, :env, :status

    APP_DIR = File.expand_path("../../", __dir__)
    SLACK_SCRIPT = File.expand_path("continuous_reporting/slack_build_notifier.rb", APP_DIR)

    def self.error(error)
      new.error(error).notify!
    end

    def initialize(body: nil, title: nil, image: nil, args: nil)
      @body = body
      @title = title
      @image = image
      @args = args
    end

    def notify!
      cmd = [
        RbConfig.ruby,
        SLACK_SCRIPT
      ]
      cmd << "--title=#{title}" if title
      cmd << "--image=#{image}" if image

      cmd << "-" if body
      cmd.concat(args) if args

      IO.popen(env || {}, cmd, 'w') do |pipe|
        pipe.write(body) if body
      end

      @status = $?

      return @status.success?
    end
  end
end
