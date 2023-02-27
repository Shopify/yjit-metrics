class MemoryTimelineReport < YJITMetrics::TimelineReport
  def self.report_name
    "memory_timeline"
  end

  def self.report_extensions
    [ "html", "recent.html" ]
  end

  # These objects have *gigantic* internal state. For debuggability, don't print the whole thing.
  def inspect
    "MemoryTimelineReport<#{object_id}>"
  end

  REPORT_PLATFORMS=["x86_64", "aarch64"]
  CONFIG_NAMES = {
    "no-jit" => "prod_ruby_no_jit",
    "yjit" => "prod_ruby_with_yjit",
  }
  CONFIG_ROOTS = CONFIG_NAMES.values
  NUM_RECENT=100
  def initialize(context)
    super

    ruby_config_roots = CONFIG_NAMES.values

    # This should match the JS parser in the template file
    time_format = "%Y %m %d %H %M %S"

    @series = {}
    REPORT_PLATFORMS.each { |platform| @series[platform] = { :recent => [], :all_time => [] } }

    color_idx = 0
    @context[:benchmark_order].each.with_index do |benchmark, idx|
      ruby_config_roots.each do |config_root|
        color = MUNIN_PALETTE[color_idx % MUNIN_PALETTE.size]
        color_idx += 1

        REPORT_PLATFORMS.each do |platform|
          config = "#{platform}_#{config_root}"
          points = @context[:timestamps].map do |ts|
            this_point = @context[:summary_by_timestamp].dig(ts, config, benchmark)
            if this_point
              this_ruby_desc = @context[:ruby_desc_by_config_and_timestamp][config][ts] || "unknown"
              # These fields are from the ResultSet summary - peak_mem_bytes is an array because multiple runs are possible
              [ ts.strftime(time_format), this_point["peak_mem_bytes"].max, this_ruby_desc ]
            else
              nil
            end
          end
          points.compact!
          next if points.empty?

          visible = @context[:selected_benchmarks].include?(benchmark)

          s_all_time = { config: config, benchmark: benchmark, name: "#{config_root}-#{benchmark}", platform: platform, visible: visible, color: color, data: points }
          s_recent = s_all_time.dup
          s_recent[:data] = s_recent[:data].last(NUM_RECENT)

          @series[platform][:recent].push s_recent
          @series[platform][:all_time].push s_all_time
        end
      end
    end
  end

  def write_files(out_dir)
    [:recent, :all_time].each do |duration|
      REPORT_PLATFORMS.each do |platform|
        begin
          @data_series = @series[platform][duration].select { |s| CONFIG_ROOTS.any? { |config_root| s[:config].include?(config_root) } }

          script_template = ERB.new File.read(__dir__ + "/../report_templates/memory_timeline_data_template.js.erb")
          text = script_template.result(binding)
          File.open("#{out_dir}/reports/timeline/memory_timeline.data.#{platform}.#{duration}.js", "w") { |f| f.write(text) }
        rescue
          puts "Error writing data file for #{platform} #{duration} data!"
          raise
        end
      end
    end

    script_template = ERB.new File.read(__dir__ + "/../report_templates/memory_timeline_d3_template.html.erb")
    html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
    File.open("#{out_dir}/_includes/reports/memory_timeline.html", "w") { |f| f.write(html_output) }
  end
end
