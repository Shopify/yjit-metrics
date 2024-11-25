module MetricsHarnessHelpers
  # Look and see if they have already been saved to the env.
  # If they haven't, run the command.
  module FromEnv
    def get(key)
      ENV.fetch("YM_#{key.to_s.upcase}") { Helpers.public_send(key) }
    end

    %i[
      cpu_info
      instance_id
      instance_type
    ].each do |name|
      define_method(name) { get(name) }
    end
  end

  extend FromEnv

  module Helpers
    extend self

    # Get string metadata about the running server (with "instance-type" returns "cX.metal"; Can fetch tags, etc).
    INSTANCE_INFO = File.expand_path("./instance-info.sh", __dir__)
    def instance_info(key, prefix: "meta-data/")
      `#{INSTANCE_INFO} "#{prefix}#{key}"`.strip
    end

    def instance_id
      instance_info("instance-id")
    end

    def instance_type
      instance_info("instance-type")
    end

    # Get information about the cpu (name, version).
    def cpu_info
      if RUBY_PLATFORM.include?('linux')
        # Use a command where the output includes the word Graviton.
        json = JSON.parse(`sudo lshw -C CPU -json`.strip)
        json.detect { |j| !j["disabled"] }.then do |item|
          # Examples vary but may include:
          # version: "Intel(R) Xeon(R) Platinum 8488C", product: "Xeon"
          # version: "6.143.8", product: "Intel(R) Xeon(R) Platinum 8488C"
          # version: "AWS Graviton3" product: "ARMv8 (N/A)"
          # version: "AWS Graviton4" product: "(N/A)"
          if item["version"].include?(item["product"])
            item["version"]
          else
            [item["product"].delete_suffix('(N/A)').strip, item["version"]].reject(&:empty?).join(": ")
          end
        end
      elsif RUBY_PLATFORM.include?('darwin')
        # "Apple M3 Pro"
        `sysctl -n machdep.cpu.brand_string`.strip
      end
    end
  end
end
