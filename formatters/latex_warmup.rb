#!/usr/bin/env ruby

# This is an example of turning a CSV file into a simple LaTeX table.
# This one works with the CSV output of the warmup report.

if ARGV.size != 1
    $stderr.puts "Usage: #{$0} <csv file from warmup report>"
    exit 1
end

lines = File.readlines ARGV[0]
header = lines[0]
data = lines[1..-1]

header_cols = header.split(",")
num_cols = header_cols.size
num_iters = (num_cols - 2) / 2

def escape_latex(s)
    s.gsub("#", "\\#").gsub("_", "\\_")
end

# Escape the hash sign in strings like "iter #50"
iter_names = header_cols[2..(num_iters+1)].map { |name| escape_latex(name) }
formatted_output = []

# Formatting the individual table entries for LaTeX
data.each do |line|
    cols = line.split(",")
    bench_name = escape_latex(cols[0])
    iter_means = cols[2..(num_iters+1)].map(&:to_f)
    iter_rsd_pcts = cols[(num_iters+2)..-1].map(&:to_f)

    latex_cols = iter_means.zip(iter_rsd_pcts).map { |mean, rsdp| format("%2.f \\pm %.2f\\%%", mean, rsdp) }
    formatted_output.push [bench_name] + latex_cols
end

# LaTeX output
latex_header = <<~LATEX_HEADER
    \\begin{center}
    \\begin{tabular}{||#{ (["c"] * (num_iters + 1)).join(" ") }||}
    \\hline
    Benchmark & #{ iter_names.join(" & ") } \\\\ [0.5ex]
    \\hline\\hline
LATEX_HEADER

latex_middle = formatted_output.map { |line| line.join(" & ") + " \\\\\n" }.join("\\hline\n")

latex_footer = <<~LATEX_FOOTER
    \\hline
    \\end{tabular}
    \\end{center}
LATEX_FOOTER

puts latex_header + latex_middle + latex_footer
