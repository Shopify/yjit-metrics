# frozen_string_literal: true
require "victor"

require_relative "./bloggable_single_report"

module YJITMetrics
  # This report is to compare YJIT's speedup versus other Rubies for a single run or block of runs,
  # with a single YJIT head-of-master.
  class SpeedDetailsReport < BloggableSingleReport
    # This report requires a platform name and can't be auto-instantiated by basic_report.rb.
    # Instead, its child report(s) can instantiate it for a specific platform.
    #def self.report_name
    #  "blog_speed_details"
    #end

    def self.report_extensions
      [ "html", "svg", "head.svg", "back.svg", "micro.svg", "tripwires.json", "csv" ]
    end

    def initialize(orig_config_names, results, platform:, benchmarks: [])
      # Dumb hack for subclasses until we refactor everything.
      return super(orig_config_names, results, benchmarks: benchmarks) unless self.class == YJITMetrics::SpeedDetailsReport

      unless YJITMetrics::PLATFORMS.include?(platform)
        raise "Invalid platform for #{self.class.name}: #{platform.inspect}!"
      end
      @platform = platform

      # Permit non-same-platform stats config
      config_names = orig_config_names.select { |name| name.start_with?(platform) || name.include?("yjit_stats") }
      raise("Can't find any stats configuration in #{orig_config_names.inspect}!") if config_names.empty?

      # Set up the parent class, look up relevant data
      super(config_names, results, benchmarks: benchmarks)
      return if @inactive # Can't get stats? Bail out.

      look_up_data_by_ruby

      # Sort benchmarks by headline/micro category, then alphabetically
      @benchmark_names.sort_by! { |bench_name| [ benchmark_category_index(bench_name), bench_name ] }

      @headings = [ "bench" ] +
        @configs_with_human_names.flat_map { |name, config| [ "#{name} (ms)", "#{name} RSD" ] } +
        @configs_with_human_names.flat_map { |name, config| config == @baseline_config ? [] : [ "#{name} spd", "#{name} spd RSD" ] } +
        [ "% in YJIT" ]

      # Col formats are only used when formatting entries for a text table, not for CSV
      @col_formats = [ bench_name_link_formatter ] +
        [ "%.1f", "%.2f%%" ] * @configs_with_human_names.size +     # Mean and RSD per-Ruby
        [ "%.2fx", "%.2f%%" ] * (@configs_with_human_names.size - 1) +  # Speedups per-Ruby
        [ "%.2f%%" ]                          # YJIT ratio

      @col_formats[13] = "<b>%.2fx</b>" # Boldface the YJIT speedup column.

      calc_speed_stats_by_config
    end

    # Printed to console
    def report_table_data
      @benchmark_names.map.with_index do |bench_name, idx|
        [ bench_name ] +
          @configs_with_human_names.flat_map { |name, config| [ @mean_by_config[config][idx], @rsd_pct_by_config[config][idx] ] } +
          @configs_with_human_names.flat_map { |name, config| config == @baseline_config ? [] : @speedup_by_config[config][idx] } +
          [ @yjit_ratio[idx] ]
      end
    end

    # Listed on the details page
    def details_report_table_data
      @benchmark_names.map.with_index do |bench_name, idx|

        [ bench_name ] +
          @configs_with_human_names.flat_map { |name, config| [ @mean_by_config[config][idx], @rsd_pct_by_config[config][idx] ] } +
          @configs_with_human_names.flat_map { |name, config| config == @baseline_config ? [] : @speedup_by_config[config][idx] } +
          [ @yjit_ratio[idx] ]
      end
    end

    def to_s
      # This is just used to print the table to the console
      format_as_table(@headings, @col_formats, report_table_data) +
        "\nRSD is relative standard deviation (stddev / mean), expressed as a percent.\n" +
        "Spd is the speed (iters/second) of the optimised implementation -- 2.0x would be twice as many iters per second.\n"
    end

    # For the SVG, we calculate ratios from 0 to 1 for how far across the graph area a coordinate is.
    # Then we convert them here to the actual size of the graph.
    def ratio_to_x(ratio)
      (ratio * 1000).to_s
    end

    def ratio_to_y(ratio)
      (ratio * 600.0).to_s
    end

    def svg_object(relative_values_by_config_and_benchmark, benchmarks: @benchmark_names)
      svg = Victor::SVG.new :template => :minimal,
        :viewBox => "0 0 1000 600",
        :xmlns => "http://www.w3.org/2000/svg",
        "xmlns:xlink" => "http://www.w3.org/1999/xlink"  # background: '#ddd'

      # Reserve some width on the left for the axis. Include a bit of right-side whitespace.
      left_axis_width = 0.05
      right_whitespace = 0.01

      # Reserve some height for the legend and bottom height for x-axis labels
      bottom_key_height = 0.17
      top_whitespace = 0.05

      plot_left_edge = left_axis_width
      plot_top_edge = top_whitespace
      plot_bottom_edge = 1.0 - bottom_key_height
      plot_width = 1.0 - left_axis_width - right_whitespace
      plot_height = 1.0 - bottom_key_height - top_whitespace
      plot_right_edge = 1.0 - right_whitespace

      svg.rect x: ratio_to_x(plot_left_edge), y: ratio_to_y(plot_top_edge),
        width: ratio_to_x(plot_width), height: ratio_to_y(plot_height),
        stroke: Theme.axis_color,
        fill: Theme.background_color


      # Basic info on Ruby configs and benchmarks
      ruby_configs = @configs_with_human_names.map { |name, config| config }
      ruby_human_names = @configs_with_human_names.map(&:first)
      ruby_config_bar_colour = Hash[
        Theme.ruby_bar_chart_color_order
          .map { |name| ruby_configs.detect { |r| r.end_with?("_#{name}") } }
          .zip(Theme.bar_chart_colors)
      ]
      baseline_colour = ruby_config_bar_colour[@baseline_config]
      baseline_strokewidth = 2
      n_configs = ruby_configs.size
      n_benchmarks = benchmarks.size


      # How high do ratios go?
      max_value = benchmarks.map do |bench_name|
        bench_idx = @benchmark_names.index(bench_name)
        relative_values_by_config_and_benchmark.values.map { |by_bench| by_bench[bench_idx][0] }.compact.max
      end.max

      if max_value.nil?
        $stderr.puts "Error finding Y axis. Benchmarks: #{benchmarks.inspect}."
        $stderr.puts "data: #{relative_values_by_config_and_benchmark.inspect}"
        raise "Error finding axis Y scale for benchmarks: #{benchmarks.inspect}"
      end

      # Now let's calculate some widths...

      # Within each benchmark's horizontal span we'll want 3 or 4 bars plus a bit of whitespace.
      # And we'll reserve 5% of the plot's width for whitespace on the far left and again on the far right.
      plot_padding_ratio = 0.05
      plot_effective_width = plot_width * (1.0 - 2 * plot_padding_ratio)
      plot_effective_left = plot_left_edge + plot_width * plot_padding_ratio

      # And some heights...
      plot_top_whitespace = 0.15 * plot_height
      plot_effective_top = plot_top_edge + plot_top_whitespace
      plot_effective_height = plot_height - plot_top_whitespace

      # Add axis markers down the left side
      tick_length = 0.008
      font_size = "small"
      # This is the largest power-of-10 multiple of the no-JIT mean that we'd see on the axis. Often it's 1 (ten to the zero.)
      largest_power_of_10 = 10.0 ** Math.log10(max_value).to_i
      # Let's get some nice even numbers for possible distances between ticks
      candidate_division_values =
        [ largest_power_of_10 * 5, largest_power_of_10 * 2, largest_power_of_10, largest_power_of_10 / 2, largest_power_of_10 / 5,
          largest_power_of_10 / 10, largest_power_of_10 / 20 ]
      # We'll try to show between about 4 and 10 ticks along the axis, at nice even-numbered spots.
      division_value = candidate_division_values.detect do |div_value|
        divs_shown = (max_value / div_value).to_i
        divs_shown >= 4 && divs_shown <= 10
      end
      raise "Error figuring out axis scale with max ratio: #{max_value.inspect} (pow10: #{largest_power_of_10.inspect})!" if division_value.nil?
      division_ratio_per_value = plot_effective_height / max_value

      # Now find all the y-axis tick locations
      divisions = []
      cur_div = 0.0
      loop do
        divisions.push cur_div
        cur_div += division_value
        break if cur_div > max_value
      end

      divisions.each do |div_value|
        tick_distance_from_zero = div_value / max_value
        tick_y = plot_effective_top + (1.0 - tick_distance_from_zero) * plot_effective_height
        svg.line x1: ratio_to_x(plot_left_edge - tick_length), y1: ratio_to_y(tick_y),
          x2: ratio_to_x(plot_left_edge), y2: ratio_to_y(tick_y),
          stroke: Theme.axis_color
        svg.text ("%.1f" % div_value),
          x: ratio_to_x(plot_left_edge - 3 * tick_length), y: ratio_to_y(tick_y),
          text_anchor: "end",
          font_weight: "bold",
          font_size: font_size,
          fill: Theme.text_color
      end

      # Set up the top legend with coloured boxes and Ruby config names
      top_legend_box_height = 0.032
      top_legend_box_width = 0.12
      text_height = 0.015

      top_legend_item_width = plot_effective_width / n_configs
      n_configs.times do |config_idx|
        item_center_x = plot_effective_left + top_legend_item_width * (config_idx + 0.5)
        item_center_y = plot_top_edge + 0.025
        legend_text_color = Theme.text_on_bar_color
        if @configs_with_human_names[config_idx][1] == @baseline_config
          legend_text_color = Theme.axis_color
          left = item_center_x - 0.5 * top_legend_box_width
          y = item_center_y - 0.5 * top_legend_box_height + top_legend_box_height
          svg.line \
          x1: ratio_to_x(left),
          y1: ratio_to_y(y),
          x2: ratio_to_x(left + top_legend_box_width),
          y2: ratio_to_y(y),
          stroke: baseline_colour,
          "stroke-width": 2
        else
          svg.rect \
          x: ratio_to_x(item_center_x - 0.5 * top_legend_box_width),
          y: ratio_to_y(item_center_y - 0.5 * top_legend_box_height),
          width: ratio_to_x(top_legend_box_width),
          height: ratio_to_y(top_legend_box_height),
          fill: ruby_config_bar_colour[ruby_configs[config_idx]],
          **Theme.legend_box_attrs
        end
        svg.text @configs_with_human_names[config_idx][0],
          x: ratio_to_x(item_center_x),
          y: ratio_to_y(item_center_y + 0.5 * text_height),
          font_size: font_size,
          text_anchor: "middle",
          font_weight: "bold",
          fill: legend_text_color,
          **(legend_text_color == Theme.text_on_bar_color ? Theme.legend_text_attrs : {})
      end

      baseline_y = plot_effective_top + (1.0 - (1.0 / max_value)) * plot_effective_height

      bar_data = []

      # We could draw the baseline here to put it behind the bars.

      # Okay. Now let's plot a lot of boxes and whiskers.
      benchmarks.each.with_index do |bench_name, bench_short_idx|
        bar_data << {label: bench_name.delete_suffix('.rb'), bars: []}
        bench_idx = @benchmark_names.index(bench_name)

        ruby_configs.each.with_index do |config, config_idx|
          human_name = ruby_human_names[config_idx]

          relative_value, rsd_pct = relative_values_by_config_and_benchmark[config][bench_idx]

          if config == @baseline_config
            # Sanity check.
            raise "Unexpected relative value for baseline config" if relative_value != 1.0
          end

          # If relative_value is nil, there's no such benchmark in this specific case.
          if relative_value != nil
            rsd_ratio = rsd_pct / 100.0
            bar_height_ratio = relative_value / max_value

            # The calculated number is rel stddev and is scaled by bar height.
            stddev_ratio = bar_height_ratio * rsd_ratio

            tooltip_text = "#{"%.2f" % relative_value}x baseline (#{human_name})"

            if config == @baseline_config
              next
            end

            bar_data.last[:bars] << {
              value: bar_height_ratio,
              fill: ruby_config_bar_colour[config],
              label: sprintf("%.2f", relative_value),
              tooltip: tooltip_text,
              stddev_ratio: stddev_ratio,
            }
          end
        end
      end

      geomeans = ruby_configs.each_with_object({}) do |config, h|
        next unless relative_values_by_config_and_benchmark[config]
        values = benchmarks.map { |bench| relative_values_by_config_and_benchmark[config][ @benchmark_names.index(bench) ]&.first }.compact
        h[config] = geomean(values)
      end

      bar_data << {
        label: "geomean*",
        label_attrs: {font_style: "italic"},
        bars: ruby_configs.map.with_index do |config, index|
        next if config == @baseline_config
        value = geomeans[config]
        {
          value: value / max_value,
          fill: ruby_config_bar_colour[config],
          label: sprintf("%.2f", value),
          tooltip: sprintf("%.2fx baseline (%s)", value, ruby_human_names[index]),
        }
        end.compact,
      }

      # Determine bar width by counting the bars and adding the number of groups
      # for bar-sized space before each group, plus one for the right side of the graph.
      num_groups = bar_data.size
      bar_width = plot_width / (num_groups + bar_data.map { |x| x[:bars].size }.sum + 1)

      bar_labels = []

      # Start at the y-axis.
      left = plot_left_edge
      bar_data.each.with_index do |data, group_index|
        data[:bars].each.with_index do |bar, bar_index|
        # Move position one width over to place this bar.
        left += bar_width

        bar_left = left
        bar_center = bar_left + 0.5 * bar_width
        bar_right = bar_left + bar_width
        bar_top = plot_effective_top + (1.0 - bar[:value]) * plot_effective_height
        bar_height = bar[:value] * plot_effective_height

        svg.rect \
          x: ratio_to_x(bar_left),
          y: ratio_to_y(bar_top),
          width: ratio_to_x(bar_width),
          height: ratio_to_y(bar_height),
          fill: bar[:fill],
          data_tooltip: bar[:tooltip]

        if bar[:label]
          bar_labels << {
          x: bar_left + 0.002,
          y: bar_top - 0.0125,
          text: bar[:label],
          }
        end

        if bar[:stddev_ratio]&.nonzero?
          # Whiskers should be centered around the top of the bar, at a distance of one stddev.
          stddev_top = bar_top - bar[:stddev_ratio] * plot_effective_height
          stddev_bottom = bar_top + bar[:stddev_ratio] * plot_effective_height

          svg.line \
          x1: ratio_to_x(bar_left),
          y1: ratio_to_y(stddev_top),
          x2: ratio_to_x(bar_right),
          y2: ratio_to_y(stddev_top),
          **Theme.stddev_marker_attrs
          svg.line \
          x1: ratio_to_x(bar_left),
          y1: ratio_to_y(stddev_bottom),
          x2: ratio_to_x(bar_right),
          y2: ratio_to_y(stddev_bottom),
          **Theme.stddev_marker_attrs
          svg.line \
          x1: ratio_to_x(bar_center),
          y1: ratio_to_y(stddev_top),
          x2: ratio_to_x(bar_center),
          y2: ratio_to_y(stddev_bottom),
          **Theme.stddev_marker_attrs
        end
        end

        # Place a tick on the x-axis in the middle of the group and print label.
        group_right = left + bar_width
        group_left = (group_right - (bar_width * data[:bars].size))
        middle = group_left + (group_right - group_left) / 2
        svg.line \
        x1: ratio_to_x(middle),
        y1: ratio_to_y(plot_bottom_edge),
        x2: ratio_to_x(middle),
        y2: ratio_to_y(plot_bottom_edge + tick_length),
        stroke: Theme.axis_color

        text_end_x = middle
        text_end_y = plot_bottom_edge + tick_length * 3
        svg.text data[:label],
        x: ratio_to_x(text_end_x),
        y: ratio_to_y(text_end_y),
        fill: Theme.text_color,
        font_size: font_size,
        text_anchor: "end",
        transform: "rotate(-60, #{ratio_to_x(text_end_x)}, #{ratio_to_y(text_end_y)})",
        **data.fetch(:label_attrs, {})

        # After a group of bars leave the space of one bar width before the next group.
        left += bar_width
      end

      # Horizontal line for baseline of CRuby at 1.0.
      svg.line x1: ratio_to_x(plot_left_edge), y1: ratio_to_y(baseline_y), x2: ratio_to_x(plot_right_edge), y2: ratio_to_y(baseline_y), stroke: baseline_colour, "stroke-width": baseline_strokewidth

      # Do value labels last so that they are above bars, variance whiskers, etc.
      bar_labels.each do |label|
        font_size = "0.5em" # xx-small is equivalent to 9px or 0.5625em at the default browser font size.
        label_text_height = text_height * 0.8
        text_length = 0.0175
        transform = "rotate(-60, #{ratio_to_x(label[:x] + (bar_width * 0.5))}, #{ratio_to_y(label[:y])})"

        svg.rect \
        x: ratio_to_x(label[:x] - text_length * 0.01),
        y: ratio_to_y(label[:y] - 0.925 * label_text_height),
        width: ratio_to_x(text_length * 1.02),
        height: ratio_to_y(label_text_height),
        transform: transform,
        **Theme.bar_text_background_attrs

        svg.text label[:text],
        x: ratio_to_x(label[:x]),
        y: ratio_to_y(label[:y]),
        fill: Theme.text_color,
        font_size: font_size,
        text_anchor: "start",
        textLength: ratio_to_x(text_length),
        transform: transform,
        **Theme.bar_text_attrs
      end

      svg
    end

    def tripwires
      tripwires = {}
      micro = micro_benchmarks
      @benchmark_names.each_with_index do |bench_name, idx|
        tripwires[bench_name] = {
          mean: @mean_by_config[@with_yjit_config][idx],
          rsd_pct: @rsd_pct_by_config[@with_yjit_config][idx],
          micro: micro.include?(bench_name),
        }
      end
      tripwires
    end

    def html_template_path
      File.expand_path("../report_templates/blog_speed_details.html.erb", __dir__)
    end

    def relative_values_by_config_and_benchmark
      @speedup_by_config
    end

    def write_file(filename)
      if @inactive
        # Can't get stats? Write an empty file.
        self.class.report_extensions.each do |ext|
          File.open(filename + ".#{@platform}.#{ext}", "w") { |f| f.write("") }
        end

        return
      end

      head_bench = headline_benchmarks
      micro_bench = micro_benchmarks
      back_bench = @benchmark_names - head_bench - micro_bench

      if head_bench.empty?
        puts "Warning: when writing file #{filename.inspect}, headlining benchmark list is empty!"
      end
      if micro_bench.empty?
        puts "Warning: when writing file #{filename.inspect}, micro benchmark list is empty!"
      end
      if back_bench.empty?
        puts "Warning: when writing file #{filename.inspect}, miscellaneous benchmark list is empty!"
      end

      [
        [ @benchmark_names, ".svg" ],
        [ head_bench, ".head.svg" ],
        [ micro_bench, ".micro.svg" ],
        [ back_bench, ".back.svg" ],
      ].each do |bench_names, extension|
        if bench_names.empty?
          contents = ""
        else
          contents = svg_object(relative_values_by_config_and_benchmark, benchmarks: bench_names).render
        end

        File.open(filename + "." + @platform + extension, "w") { |f| f.write(contents) }
      end

      # First the 'regular' details report, with tables and text descriptions
      script_template = ERB.new File.read(html_template_path)
      html_output = script_template.result(binding)
      File.open(filename + ".#{@platform}.html", "w") { |f| f.write(html_output) }

      # The Tripwire report is used to tell when benchmark performance drops suddenly
      json_data = tripwires
      File.open(filename + ".#{@platform}.tripwires.json", "w") { |f| f.write JSON.pretty_generate json_data }

      write_to_csv(filename + ".#{@platform}.csv", [@headings] + report_table_data)
    end
  end
end
