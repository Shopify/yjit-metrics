# frozen_string_literal: true
# Class for reports that use a longer series of times, each with its own report/data.
module YJITMetrics
  class TimelineReport
    # This is the Munin palette from Shutterstock Rickshaw
    MUNIN_PALETTE = [
        '#00cc00',
        '#0066b3',
        '#ff8000',
        '#ffcc00',
        '#330099',
        '#990099',
        '#ccff00',
        '#ff0000',
        '#808080',
        '#008f00',
        '#00487d',
        '#b35a00',
        '#b38f00',
        '#6b006b',
        '#8fb300',
        '#b30000',
        '#bebebe',
        '#80ff80',
        '#80c9ff',
        '#ffc080',
        '#ffe680',
        '#aa80ff',
        '#ee00cc',
        '#ff8080',
        '#666600',
        '#ffbfff',
        '#00ffcc',
        '#cc6699',
        '#999900',
        # If we add one colour we get 29 entries, it's not divisible by the number of platforms and won't get weird repeats
        '#003399',
    ]

    include YJITMetrics::Stats

    def self.subclasses
      @subclasses ||= []
      @subclasses
    end

    def self.inherited(subclass)
      YJITMetrics::TimelineReport.subclasses.push(subclass)
    end

    def self.report_name_hash
      out = {}

      @subclasses.select { |s| s.respond_to?(:report_name) }.each do |subclass|
        name = subclass.report_name

        raise "Duplicated report name: #{name.inspect}!" if out[name]

        out[name] = subclass
      end

      out
    end

    def initialize(context)
      @context = context
    end

    # Look for "PLATFORM_#{name}"; prefer specified platform if present.
    def find_config(name, platform: "x86_64")
      matches = @context[:configs].select { |c| c.end_with?(name) }
      matches.detect { |c| c.start_with?(platform) } || matches.first
    end

    # Strip PLATFORM from beginning of name
    def platform_of_config(config)
      YJITMetrics::PLATFORMS.each do |p|
        return p if config.start_with?("#{p}_")
      end

      raise "Unknown platform in config '#{config}'"
    end
  end
end
