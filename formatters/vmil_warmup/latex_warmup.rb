#!/usr/bin/env ruby

# This is an example of turning a CSV file into a simple LaTeX table.
# This one works with the CSV output of the warmup report.

if ARGV.size != 1
    $stderr.puts "Usage: #{$0} <csv dir>"
    exit 1
end

csv_files = Dir["#{ARGV[0]}/*.csv"].to_a

def escape_latex(s)
    s.gsub("#", "\\#").gsub("_", "\\_")
end

def time_and_rsdp_to_latex(time_ms, rsdp)
    format("%2.f \\pm %.2f\\%%", time_ms, rsdp)
end

configs = {
    "Int" => "no_jit",
    "YJIT" => "with_yjit",
    "MJIT" => "with_mjit",
    "Truf" => "truffleruby",
}

formatted_output = {
    #"no_jit" => {
    #    "activerecord" => {
    #        Iter num formatted string => value formatted string
    #    },
    #},
}

# This should be the same for all four CSVs
iter_names = []

configs.each do |human_name, filename_section|
    for_this_config = csv_files.select { |f| f.include?(filename_section) }
    if for_this_config.size != 1
        raise "Found #{for_this_config.size} filenames for #{filename_section}, not one! Filenames: #{for_this_config.inspect}; candidates: #{csv_files.inspect}!"
    end

    formatted_output[filename_section] = {}

    lines = File.readlines for_this_config[0]
    header = lines[0]
    data = lines[1..-1]

    header_cols = header.split(",")
    num_cols = header_cols.size
    num_iters = (num_cols - 2) / 2

    # Escape the hash sign in strings like "iter #50"
    iter_names = header_cols[2..(num_iters+1)].map { |name| escape_latex(name) }

    # Escaping and formatting the individual table entries for LaTeX
    data.each do |line|
        cols = line.split(",")
        bench_name = escape_latex(cols[0])
        iter_means = cols[2..(num_iters+1)].map(&:to_f)
        iter_rsd_pcts = cols[(num_iters+2)..-1].map(&:to_f)

        latex_cols = iter_means.zip(iter_rsd_pcts).map { |mean, rsdp| time_and_rsdp_to_latex(mean,rsdp) }

        formatted_output[filename_section][bench_name] = {}
        iter_names.each_with_index do |iter_name, idx|
            #$stderr.puts "Writing #{iter_name.inspect}: #{latex_cols[idx].inspect}"
            formatted_output[filename_section][bench_name][iter_name] = latex_cols[idx]
        end
    end
end

# Cols: 4 rubies * 2 benchmarks
# Rows: iter numbers

# \\documentclass{article}
# \\usepackage{multirow}

# LaTeX output
latex_header = <<~LATEX_HEADER
    \\begin{center}
    \\begin{tabular}{||#{ (["c"] * 9).join(" ") }||}
    \\hline
    #{ (["Iter"] + ["AR & RB"] * 4).join(" & ") } \\\\ [0.5ex]
    \\hline\\hline
LATEX_HEADER

cols = [
    [ "no_jit", "activerecord" ],
    [ "no_jit", "railsbench" ],
    [ "with_yjit", "activerecord" ],
    [ "with_yjit", "railsbench" ],
    [ "with_mjit", "activerecord" ],
    [ "with_mjit", "railsbench" ],
    [ "truffleruby", "activerecord" ],
    [ "truffleruby", "railsbench" ],
]

latex_middle = iter_names.map do |iter_name|
    formatted_cols = cols.map do |config, bench|
        formatted_output[config][bench][iter_name]
    end

    row = iter_name + " & " + formatted_cols.join(" & ") + " \\\\\n"
    row
end.join("\\hline\n")

latex_footer = <<~LATEX_FOOTER
    \\hline
    \\end{tabular}
    \\end{center}
LATEX_FOOTER

puts latex_header + latex_middle + latex_footer
