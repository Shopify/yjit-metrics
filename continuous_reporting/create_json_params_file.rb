#!/usr/bin/env ruby

require "optparse"
require "json"

YJIT_METRICS_DIR = File.expand_path(__dir__, "..")
yjit_metrics_sha = nil

out_file = "bench_params.json"
output_ts = Time.now.getgm.strftime('%F-%H%M%S')
cruby_sha = ""

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: create_json_params_file.rb [options]

    BANNER

    opts.on("-ot TS", "--output-timestamp TS") do |ts|
        output_ts = ts
    end

    opts.on("-ym TS", "--yjit-metrics-name YM") do |ym|
        # Blank yjit_metrics rev? Use main.
        ym = "main" if ym.nil? || ym.strip == ""
        yjit_metrics_name = ym
    end

    # TODO: change or remove
    opts.on("-g", "--no-gh-issue", "Do not file an actual GitHub issue, only print failures to console") do
        should_file_gh_issue = false
    end

end.parse!

def sha_for_name_in_dir(name:, dir:, desc:)
    Dir.chdir(dir) do
        system("git checkout #{name}") || raise("Cannot checkout #{desc} revision #{name}")
        return `git rev-parse HEAD`.trim
    end
end

yjit_metrics_sha = sha_for_name_in_dir name: yjit_metrics_name, dir: YJIT_METRICS_DIR, desc: "yjit_metrics"

output = {
    ts: output_ts,
    cruby_sha: cruby_sha,
    yjit_bench_sha: yjit_bench_sha,
    yjit_metrics_sha: yjit_metrics_sha,
}

puts "Writing file: #{out_file}..."
File.open(out_file, "w") { |f| f.write JSON.pretty_generate(output) }
