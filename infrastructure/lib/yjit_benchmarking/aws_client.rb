# frozen_string_literal: true

require "aws-sdk-ec2"

module YJITBenchmarking
  class AwsClient
    attr_reader :ec2

    SSH_USER = "ubuntu"

    def initialize
      @default_filters = [
        {name: "tag:Project", values: ["YJIT"]},
      ]
      # Expects env: AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
      @ec2 = Aws::EC2::Client.new
    end

    def find(filters:)
      ec2.describe_instances(
        filters:
          @default_filters +
          filters,
      # Aws::Ec2::Instance.new(i.id, client: ec2)
      )&.reservations&.map(&:instances)&.flatten
    end

    def find_by_name(names)
      names = array_wrap(names)
      count = names.count

      instances = find(
        filters: [
          {name: "tag:Name", values: names},
        ],
      ).reject { |i| i.state.name == "terminated" }

      if instances&.size != count
        raise "Instance confusion! Expected #{count} received #{instances&.size.inspect}"
      end

      instances
    end

    def name(instance)
      instance.tags.detect { |t| t.key == "Name" }.value
    end

    def start_time(instance)
      instance.launch_time
    end

    def info(instance)
      {
        name: name(instance),
        state: instance.state.name,
        address: instance.public_ip_address,
        start_time: start_time(instance),
      }
    end

    def ssh_destination(instance)
      "#{SSH_USER}@#{instance.public_ip_address}"
    end

    def ensure_in_state!(instances, state:)
      instances = array_wrap(instances)
      instance_ids = instances.map(&:instance_id)
      in_state = find(filters: [
        {name: "instance-state-name", values: array_wrap(state)},
        {name: "instance-id", values: instance_ids},
      ])

      if in_state.size != instance_ids.size
        expected_names = instances.map { |x| name(x) }
        actual_names = in_state.map { |x| name(x) }

        raise "Failed to find #{expected_names - actual_names} in state #{state.inspect}"
      end
    end

    def start(instances, state: nil)
      instances = array_wrap(instances)
      ensure_in_state!(instances, state:) if state

      params = { instance_ids: instances.map(&:instance_id) }

      ec2.start_instances(params)
      ec2.wait_until(:instance_status_ok, params, before_attempt: proc do
        STDERR.puts "Waiting for instance#{"s" if instances.count != 1} to be ready..."
      end)
      ec2.describe_instances(params)&.reservations&.map(&:instances)&.flatten
    end

    def stop(instances)
      instances = array_wrap(instances)
      params = { instance_ids: instances.map(&:instance_id) }

      ec2.stop_instances(params)
      ec2.wait_until(:instance_stopped, params, before_attempt: proc do
        STDERR.puts "Waiting for instance#{"s" if instances.count != 1} to stop..."
      end)
    end

    # Array() calls #to_a which Struct defines to return the attributes
    # so we need something else for calling on AWS responses.
    def array_wrap(x)
      x.is_a?(Array) ? x : [x]
    end
  end
end
