# frozen_string_literal: true

require "erb"

# Shared utility methods for reports that use a single "blob" of results
module YJITMetrics
  class Report
    Theme = YJITMetrics::Theme

    include YJITMetrics::Stats

    def self.subclasses
      @subclasses ||= []
      @subclasses
    end

    def self.inherited(subclass)
      YJITMetrics::Report.subclasses.push(subclass)
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

    def initialize(config_names, results, benchmarks: [])
      raise "No Rubies specified for report!" if config_names.empty?

      bad_configs = config_names - results.available_configs
      raise "Unknown configurations in report: #{bad_configs.inspect}!" unless bad_configs.empty?

      @config_names = config_names
      @only_benchmarks = benchmarks
      @result_set = results
    end

    # Child classes can accept params in this way. By default it's a no-op.
    def set_extra_info(info)
      @extra_info = info
    end

    # Do we specifically recognize this extra field? Nope. Child classes can override.
    def accepts_field(name)
      false
    end

    def filter_benchmark_names(names)
      return names if @only_benchmarks.empty?
        names.select { |bench_name| @only_benchmarks.any? { |bench_spec| bench_name.start_with?(bench_spec) } }
    end

    # Take column headings, formats for the percent operator and data, and arrange it
    # into a simple ASCII table returned as a string.
    def format_as_table(headings, col_formats, data, separator_character: "-", column_spacer: "  ")
      out = +""

      unless data && data[0] && col_formats && col_formats[0] && headings && headings[0]
        $stderr.puts "Error in format_as_table..."
        $stderr.puts "Headings: #{headings.inspect}"
        $stderr.puts "Col formats: #{col_formats.inspect}"
        $stderr.puts "Data: #{data.inspect}"
        raise "Invalid data sent to format_as_table"
      end

      num_cols = data[0].length
      raise "Mismatch between headings and first data row for number of columns!" unless headings.length == num_cols
      raise "Data has variable number of columns!" unless data.all? { |row| row.length == num_cols }
      raise "Column formats have wrong number of entries!" unless col_formats.length == num_cols

      formatted_data = data.map.with_index do |row, idx|
        col_formats.zip(row).map { |fmt, item| item ? fmt % item : "" }
      end

      col_widths = (0...num_cols).map { |col_num| (formatted_data.map { |row| row[col_num].length } + [ headings[col_num].length ]).max }

      out.concat(headings.map.with_index { |h, idx| "%#{col_widths[idx]}s" % h }.join(column_spacer), "\n")

      separator = col_widths.map { |width| separator_character * width }.join(column_spacer)
      out.concat(separator, "\n")

      formatted_data.each do |row|
        out.concat (row.map.with_index { |item, idx| " " * (col_widths[idx] - item.size) + item }).join(column_spacer), "\n"
      end

      out.concat("\n", separator, "\n")
    rescue
      $stderr.puts "Error when trying to format table: #{headings.inspect} / #{col_formats.inspect} / #{data[0].inspect}"
      raise
    end

    def html_table(headings, col_formats, data, tooltips: [])
      ERB.new(<<~'HTML').result(binding)
        <div class="table-wrapper">
          <table>
            <thead>
              <% headings.each_with_index do |heading, idx| %>
                <th scope="col" <%= "title=#{tooltips[idx].inspect}" if tooltips %>><%= heading %></th>
              <% end %>
            </thead>
            <tbody style="text-align: right;">
              <% data.each do |row| %>
                <tr style="border: 1px solid black;">
                  <%
                    row.each_with_index do |cell, idx|
                    format = col_formats[idx]
                    tag = idx.zero? ? %(th scope="row") : "td"
                  %>
                    <<%= tag %>>
                    <%= cell.nil? ? "" : format % cell %>
                    </<%= tag.split(' ').first %>>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      HTML
    end

    def write_to_csv(filename, data)
      CSV.open(filename, "wb") do |csv|
        data.each { |row| csv << row }
      end
    end
  end
end
