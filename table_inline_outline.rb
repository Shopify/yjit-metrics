#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a table of the inline and outlined code size per benchmark.
#
# To execute, run ./table_inline_outline.rb data/path/to/yjit_stats.json
#

require "erb"
require "json"

size = -> (value) {
  units = ["B", "KiB", "MiB", "GiB"]
  unit = units.shift

  while value > 1024
    value /= 1024.0
    unit = units.shift
  end

  "%.3g %s" % [value, unit]
}

data =
  JSON.parse(File.read(ARGV.first))["yjit_stats"].map do |name, (values, *)|
    [name.gsub("_", "\\_"), size[values["inline_code_size"]], size[values["outlined_code_size"]]]
  end

data.sort_by!(&:first)
data.map! { |row| "#{row.join(" & ")} \\\\\n\\hline" }

puts ERB.new(DATA.read).result_with_hash(data: data)

__END__
\begin{table*}
\begin{center}
\begin{tabular}{|c c c|}
\hline
Benchmark & Inline code size & Outlined code size \\ [0.5ex]
\hline\hline
<%= data.join("\n") %>
\end{tabular}
\end{center}
\caption{Inline and outlined code size}
\end{table*}
