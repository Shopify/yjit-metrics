# frozen_string_literal: true

# Send notification via slack.

module YJITMetrics
  class Notifier
    attr_accessor :bench_params, :body, :title, :image, :args, :env, :status

    APP_DIR = File.expand_path("../../", __dir__)
    SLACK_SCRIPT = File.expand_path("continuous_reporting/slack_build_notifier.rb", APP_DIR)
    BACKTRACE_ITEMS = 2
    BENCH_PARAMS_TO_SHOW = ["cruby_sha", "ts", "yjit_bench_sha", "yjit_metrics_sha"]

    def initialize(body: nil, title: nil, image: nil, args: nil, bench_params: nil)
      @body = body
      @title = title
      @image = image
      @args = args
      @bench_params = bench_params
    end

    # Format notification message based on provided error object.
    # Returns self.
    def error(exception)
      body = if exception.is_a?(MetricsApp::CommandExitedNonZero)
        lines = exception.stderr.lines
        if lines.size > 10
          lines = lines.last(10)
          lines.unshift("…\n")
        end
        lines.map { |l| truncate_line(l, 200) }.join.strip
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
      @body += "bench params:\n```#{bench_params.slice(*BENCH_PARAMS_TO_SHOW).to_yaml}```\n" if bench_params

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

    def truncate_line(line, size)
      line.size > size ? line[0..size] + "…\n" : line
    end
  end
end
