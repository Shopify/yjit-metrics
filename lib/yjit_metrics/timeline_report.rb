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

    # These objects have *gigantic* internal state. For debuggability, don't print the whole thing.
    def inspect
      "#{self.class.name}<#{object_id}>"
    end

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

    # We offer graphs for "all time" and "recent".
    # Recent is just the subset of the last X results.
    NUM_RECENT = 100

    # This should match the JS parser in the template file.
    TIME_FORMAT = "%Y-%m-%d %H:%M:%S"

    def initialize(context)
      @context = context
      build_series!
    end

    def build_row(ts, this_point, this_ruby_desc)
      # These fields are from the ResultSet summary
      {
        time: ts,
        value: this_point["mean"],
        stddev: this_point["stddev"],
        ruby_desc: this_ruby_desc,
      }
    end

    def build_series!
      @series = {}
      YJITMetrics::PLATFORMS.each { |platform| @series[platform] = { :recent => [], :all_time => [] } }

      color_idx = 0
      @context[:benchmark_order].each.with_index do |benchmark, idx|
        self.class::CONFIG_NAMES.each do |config_root, config_human_name|
          color = MUNIN_PALETTE[color_idx % MUNIN_PALETTE.size]
          color_idx += 1

          YJITMetrics::PLATFORMS.each do |platform|
            config = "#{platform}_#{config_root}"
            points = @context[:timestamps].map do |ts|
              this_point = @context[:summary_by_timestamp].dig(ts, config, benchmark)
              if this_point
                this_ruby_desc = @context[:ruby_desc_by_config_and_timestamp][config][ts] || "unknown"
                build_row(ts.strftime(TIME_FORMAT), this_point, this_ruby_desc)
              else
                nil
              end
            end
            points.compact!
            next if points.empty?

            s_all_time = {
              # config: config,
              # config_human_name: config_human_name,
              benchmark: benchmark,
              name: "#{config_root}-#{benchmark}",
              platform: platform,
              color: color,
              data: points,
            }
            s_recent = s_all_time.dup
            s_recent[:data] = s_recent[:data].last(NUM_RECENT)

            @series[platform][:recent].push s_recent
            @series[platform][:all_time].push s_all_time
          end
        end
      end
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

    def data_human_name(series)
      self.class::CONFIG_NAMES[series[:name].delete_suffix("-#{series[:benchmark]}")]
    end

    def write_files(out_dir)
      [:recent, :all_time].each do |duration|
        YJITMetrics::PLATFORMS.each do |platform|
          begin
            File.open("#{out_dir}/reports/timeline/#{self.class.report_name}.data.#{platform}.#{duration}.json", "w") do |f|
              f.write(JSON.pretty_generate({data: @series[platform][duration]}))
            end
          rescue
            puts "Error writing data file for #{platform} #{duration} data!"
            raise
          end
        end
      end

      @data_series = @series.values.map { |x| x[:all_time] if !x[:all_time].empty? }.compact.first

      script_template = ERB.new File.read(File.expand_path("report_templates/#{self.class.report_name}_d3_template.html.erb", __dir__))
      html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
      File.open("#{out_dir}/_includes/reports/#{self.class.report_name}.html", "w") { |f| f.write(html_output) }
    end
  end
end
