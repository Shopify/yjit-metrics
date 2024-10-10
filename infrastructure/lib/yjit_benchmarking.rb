# frozen_string_literal: true

require_relative "yjit_benchmarking/aws_client"

module YJITBenchmarking
  class Command
    attr_reader :client

    def initialize(client = YJITBenchmarking::AwsClient.new)
      @client = client
    end

    BENCHMARKING_NAMES = ["yjit-benchmarking-x86", "yjit-benchmarking-arm"]
    REPORTING_NAME = "yjit-reporting"

    def benchmarking_instances
      client.find_by_name(BENCHMARKING_NAMES)
    end

    def reporting_instance
      client.find_by_name(REPORTING_NAME).first
    end

    def with_instances(instances, state: nil, &block)
      client.start(instances, state:).map(&block)
    end

    LAUNCH_SCRIPT = "~/ym/yjit-metrics/continuous_reporting/on_demand/launch.sh"

    # Disable host key checks
    # as the IP will be different every time
    # (and we don't want to be prompted to accept).
    SSH_OPTS = [
      "-oCheckHostIP=no",
      "-oStrictHostKeyChecking=no",
      "-oUserKnownHostsFile=/dev/null",
    ].freeze

    def ssh_opts
      SSH_OPTS + ENV['SSH_KEY_FILE'].yield_self { |x| x ? ["-oIdentityFile=#{x}"] : [] }
    end

    def ssh_exec(instance, *command, prefix: client.name(instance))
      dest = client.ssh_destination(instance)
      run_with_output_prefix(
        "ssh",
        *ssh_opts,
        dest,
        *command,
        prefix:,
      )
    end

    def run_with_output_prefix(*cmd, prefix: "")
      IO.popen(cmd) do |pipe|
        while line = pipe.readline
          STDERR.puts "#{prefix}| #{line}"
        end
      rescue EOFError
        nil
      end
    end

    # Commands

    class Benchmark < Command
      def execute(bench_params_file)
        with_instances(benchmarking_instances, state: ["stopped"]) do |instance|
          Thread.new do
            dest = client.ssh_destination(instance)
            remote_params = "~/ym/bench_params.json"
            system("scp", *ssh_opts, bench_params_file, "#{dest}:#{remote_params}")

            ssh_exec(instance, "BENCH_PARAMS=#{remote_params} #{LAUNCH_SCRIPT} benchmark")
          end
        end.map(&:join)
      end
    end

    class Report < Command
      def execute
        with_instances(reporting_instance, state: ["stopped"]) do |instance|
          ssh_exec(instance, "#{LAUNCH_SCRIPT} report")
        end
      end
    end

    class Info < Command
      def execute
        spec = "%25s %9s %15s %s\n"
        printf spec, "name", "state", "address", "last start time"
        (benchmarking_instances + [reporting_instance]).each do |instance|
          info = client.info(instance)
          printf spec, *info.values_at(:name, :state, :address, :start_time)
        end
      end
    end

    class Ssh < Command
      def execute(name, *command)
        with_instances(client.find_by_name(name)) do |instance|
          cmd = ["ssh", *ssh_opts, client.ssh_destination(instance), *command]
          puts cmd.join(" ")
          exec(*cmd)
        end
      end
    end

    class Stop < Command
      def execute(*names)
        names = BENCHMARKING_NAMES + [REPORTING_NAME] if names.empty?
        client.stop(client.find_by_name(names))
      end
    end
  end

  def self.run!(args)
    commands = Command.subclasses.to_h do |klass|
      [klass.name.split('::').last.downcase, klass]
    end

    action = args.shift
    cmd = commands[action]

    if !cmd
      actions = commands.keys
      raise "Unknown action #{action.inspect}.  Specify one of #{actions.join(", ")}"
    end

    cmd.new.execute(*args)
  end
end
