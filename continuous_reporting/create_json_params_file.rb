#!/usr/bin/env ruby

require "optparse"
require "json"

YJIT_METRICS_DIR = File.expand_path("..", __dir__)
YJIT_BENCH_DIR = File.expand_path("../yjit-bench", YJIT_METRICS_DIR)
CRUBY_DIR = File.expand_path("../prod-yjit", YJIT_METRICS_DIR)

out_file = "bench_params.json"
output_ts = Time.now.getgm.strftime('%F-%H%M%S')
cruby_name = "master"
yjit_metrics_name = "main"
yjit_bench_name = "main"

# TODO: try looking up the given yjit_metrics and/or yjit_bench and/or CRuby revisions in the local repos to see if they exist?

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: create_json_params_file.rb [options]

    BANNER

    opts.on("-ot TS", "--output-timestamp TS") do |ts|
        output_ts = ts
    end

    opts.on("-ym YM", "--yjit-metrics-name YM") do |ym|
        # Blank yjit_metrics rev? Use main.
        ym = "main" if ym.nil? || ym.strip == ""
        yjit_metrics_name = ym
    end

    opts.on("-yb YB", "--yjit-bench-name YB") do |yb|
        # Blank yjit_bench rev? Use main.
        yb = "main" if yb.nil? || yb.strip == ""
        yjit_bench_name = yb
    end

    opts.on("-cn NAME", "--cruby-name NAME") do |name|
        STDERR.puts "Setting CRuby name to #{name.inspect}..."
        name == "master" if name.nil? || name.strip == ""
        cruby_name = name.strip
    end

end.parse!

def sha_for_name_in_dir(name:, dir:, desc:)
    Dir.chdir(dir) do
        system("git fetch") || raise("Error trying to fetch latest revisions for #{desc}!")
        out = `git log -n 1 --pretty=oneline origin/#{name}`
        raise("Error trying to find SHA for #{dir.inspect} name #{name.inspect}!") unless out && out.strip != ""
        sha = out.split(" ")[0]
        raise("Output doesn't start with SHA: #{out.inspect}!") unless sha && sha =~ /\A[0-9a-zA-Z]{8}/
        return sha
    end
end

yjit_metrics_sha = sha_for_name_in_dir name: yjit_metrics_name, dir: YJIT_METRICS_DIR, desc: "yjit_metrics"
yjit_bench_sha = sha_for_name_in_dir name: yjit_bench_name, dir: YJIT_BENCH_DIR, desc: "yjit_bench"
cruby_sha = sha_for_name_in_dir name: cruby_name, dir: CRUBY_DIR, desc: "Ruby"

output = {
    ts: output_ts,
    cruby_name: cruby_name,
    cruby_sha: cruby_sha,
    yjit_bench_name: yjit_bench_name,
    yjit_bench_sha: yjit_bench_sha,
    yjit_metrics_name: yjit_metrics_name,
    yjit_metrics_sha: yjit_metrics_sha,
}

puts "Writing file: #{out_file}..."
File.open(out_file, "w") { |f| f.write JSON.pretty_generate(output) }
