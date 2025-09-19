# frozen_string_literal: true

# Send notification via slack.

module YJITMetrics
  class Notifier
    attr_accessor :body, :title, :image, :args, :env, :status

    APP_DIR = File.expand_path("../../", __dir__)
    SLACK_SCRIPT = File.expand_path("continuous_reporting/slack_build_notifier.rb", APP_DIR)
    BACKTRACE_ITEMS = 2

    def initialize(body: nil, title: nil, image: nil, args: nil)
      @body = body
      @title = title
      @image = image
      @args = args
    end

    # Format notification message based on provided error object.
    # Returns self.
    def error(exception)
      body = if exception.is_a?(MetricsApp::CommandExitedNonZero)
        exception.stderr
      else
        backtrace = exception.backtrace
          .select { |l| l.start_with?(APP_DIR) }
          .map { |l| l.delete_prefix(File.join(APP_DIR, "")) }
          .take(BACKTRACE_ITEMS)

        backtrace = exception.backtrace.take(BACKTRACE_ITEMS) if backtrace.empty?
        backtrace.map! { |l| "- #{l}" }.join("\n")
      end

      @title = "#{exception.class}: #{exception.message}"
      @image = :fail
      @body = "```\n#{body}\n```\n"

      self
    end

    # Send message to slack and return whether notification sent successfully.
    # Afterwards the `status` attribute will be populated if further inspection is desired.
    def notify!
      # Build command to use the slack script.
      cmd = [
        RbConfig.ruby,
        SLACK_SCRIPT
      ]
      cmd << "--title=#{title}" if title
      cmd << "--image=#{image}" if image

      cmd << "-" if body
      cmd.concat(args) if args

      IO.popen(env || {}, cmd, 'w') do |pipe|
        # Supply any pre-formatted body on STDIN.
        pipe.write(body) if body
      end

      @status = $?

      return @status.success?
    end
  end
end
