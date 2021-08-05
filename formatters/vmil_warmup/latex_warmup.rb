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
    # More than 100 minutes? 100 * 60 * 1_000
    if time_ms > 6_000_000
        unit = "min"
        quantity = time_ms / 60_000.0
        fmt = "%.0f"
    # More than 1 minute?
    elsif time_ms > 60_000
        unit = "min"
        quantity = time_ms / 60_000.0
        fmt = "%.1f"
    # More than 100 seconds?
    elsif time_ms > 100_000
        unit = "s"
        quantity = time_ms / 1_000.0
        fmt = "%.0f"
    # More than 1 second?
    elsif time_ms > 1_000.0
        unit = "s"
        quantity = time_ms / 1_000.0
        fmt = "%.1f"
    # More than 100 ms?
    elsif time_ms > 100
        unit = "ms"
        quantity = time_ms
        fmt = "%.0f"
    else
        unit = "ms"
        quantity = time_ms
        fmt = "%.1f"
    end

    format("$#{fmt}#{unit} \\pm %.1f\\%%$", quantity, rsdp)
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
    iter_names = header_cols[2..(num_iters+1)].map { |name| name.split("#")[-1] }

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
top_header_row = [ "No-JIT", "YJIT", "MJIT", "Truffle"].flat_map do |config|
    [ "#{config} ActiveRecord", "#{config} \\newline Railsbench" ]
end.join(" & ")
latex_header = <<~LATEX_HEADER
    \\begin{center}
    \\begin{tabular}{| #{ (["m{1.75cm}"] * 9).join(" | ") } |}
    \\hline
    Iter \\# & #{top_header_row} \\\\ [0.5ex]
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
