#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a table of the number of compiled iseqs per benchmark. Also includes
# a space for description, but doesn't include it here (it'll be written into
# the paper so it can be edited without going through a PR).
#
# To execute, run ./table_iseqs_compiled.rb data/path/to/yjit_stats.json
#

require "erb"
require "json"

data =
  JSON.parse(File.read(ARGV.first))["yjit_stats"].map do |name, (values, *)|
    [name.gsub("_", "\\_"), "", values["compiled_iseq_count"]]
  end

data.sort_by!(&:first)
data.map! { |row| "#{row.join(" & ")} \\\\\n\\hline" }

puts ERB.new(DATA.read).result_with_hash(data: data)

__END__
\begin{table*}
\begin{center}
\begin{tabular}{|sc c c|}
\hline
Benchmark & Description & Compiled iseqs \\ [0.5ex]
\hline\hline
<%= data.join("\n") %>
\end{tabular}
\end{center}
\caption{Compiled iseqs}
\end{table*}
