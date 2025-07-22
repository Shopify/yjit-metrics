# frozen_string_literal: true

require "optparse"
require_relative "yjit_benchmarking/aws_client"

module YJITBenchmarking
  class Command
    attr_reader :client, :opts

    def initialize(opts, client: YJITBenchmarking::AwsClient.new)
      @opts = opts
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

    def format_duration(seconds)
      hours, minutes = [2, 1].map { 60 ** _1 }.map { |i| (seconds / i).tap { seconds %= i } }
      sprintf "%02d:%02d:%02d", hours, minutes, seconds
    end

    # Commands

    class Benchmark < Command
      def allowed_states
        ["stopped"].concat(opts.fetch(:states) { [] })
      end

      def instances
        benchmarking_instances.select do |instance|
          opts[:only].nil? || client.name(instance).end_with?(opts[:only])
        end
      end

      def execute(bench_params_file)
        with_instances(instances, state: allowed_states) do |instance|
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
      def allowed_states
        ["stopped"].concat(opts.fetch(:states) { [] })
      end

      def ensure_stopped!
        active = benchmarking_instances.map do |instance|
          client.info(instance)
        end.select { |i| i[:state] != "stopped" }

        return if active.empty?

        desc = active.map { |i| [i[:name], i[:state]].join(':') }.join(', ')
        abort "Benchmarking instances still active! #{desc}"
      end

      def execute
        ensure_stopped!
        with_instances(reporting_instance, state: allowed_states) do |instance|
          ssh_exec(instance, "YJIT_METRICS_NAME=#{(opts[:ref]).dump} #{LAUNCH_SCRIPT} report")
        end
      end
    end

    class Info < Command
      def execute
        spec = "%25s %9s %15s %25s %14s\n"
        printf spec, "name", "state", "address", "last start time", "running time"
        (benchmarking_instances + [reporting_instance]).each do |instance|
          info = client.info(instance)
          running_time = format_duration(Time.now - info[:start_time]) if info[:state] == "running"
          printf spec, *info.values_at(:name, :state, :address, :start_time), running_time
        end
      end
    end

    class Quash < Command
      # Current running time for benchmarks is under 4 hours.
      HOURS = 5

      def describe(instance)
        info = client.info(instance)
        run_time = format_duration(Time.now - info[:start_time]) if info[:state] != "stopped"
        [
          info[:name],
          info[:state],
          run_time,
        ].compact.join(' ')
      end

      def execute(*names)
        names = BENCHMARKING_NAMES + [REPORTING_NAME] if names.empty?
        quash, leave = client.find_by_name(names).partition do |instance|
          info = client.info(instance)
          info[:state] != "stopped" && (Time.now - info[:start_time]) > (3600 * HOURS)
        end

        if !leave.empty?
          puts "Ignoring instances:", leave.map { "  - #{describe(_1)}" }
        end

        if !quash.empty?
          puts "Stopping instances:", quash.map { "  - #{describe(_1)}" }
          client.stop(quash)
          # If we had to stop long-running instances we should mark the job as
          # failed to avoid generating the reports until we check on what happened.
          exit 1
        end
      end
    end

    class Ssh < Command
      def execute(name, *command)
        with_instances(client.find_by_name(name)) do |instance|
          # Trigger terminal bell as we may have waited a while before it was ready.
          print "\a"

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

    opts = {ref: "main"}
    OptionParser.new do |op|
      op.on("--only=NAME")
      op.on("--states=STATE") do |states|
        opts[:states] = states.split(',')
      end
      op.on("--ref=ref_name") do |ref_name|
        raise("The 'ref' arg should not be empty") if ref_name.empty?
        opts[:ref] = ref_name
      end
    end.parse!(args, into: opts)

    action = args.shift
    cmd = commands[action]

    if !cmd
      actions = commands.keys
      raise "Unknown action #{action.inspect}.  Specify one of #{actions.join(", ")}"
    end

    cmd.new(opts).execute(*args)
  end
end
