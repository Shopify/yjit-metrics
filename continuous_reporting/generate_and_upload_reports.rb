#!/usr/bin/env ruby

require "json"
require "yaml"
require "fileutils"
require "optparse"

require_relative "../lib/yjit-metrics"

# Slight subtlety: this repo is currently not public, so we need a token to pull or clone it.
raise "Please set YJIT_METRICS_GITHUB_TOKEN to an appropriate GitHub token!" unless ENV["YJIT_METRICS_GITHUB_TOKEN"]
GITHUB_TOKEN = ENV["YJIT_METRICS_GITHUB_TOKEN"].chomp
YJIT_METRICS_DIR = File.expand_path File.join(__dir__, "../../yjit-metrics-pages")
YJIT_METRICS_GIT_URL = "https://#{GITHUB_TOKEN}@github.com/Shopify/yjit-metrics.git"
YJIT_METRICS_PAGES_BRANCH = "pages"

REPORTS_AND_FILES = {
    "blog_speed_headline" => {
        report_type: :basic,
        extensions: [ "html" ],
    },
    "blog_speed_details" => {
        report_type: :basic,
        extensions: [ "html", "svg" ],
    },
    #"timeline" => {
    #    report_type: :timeline,
    #    extensions: [ "html", "svg" ],
    #},
}
REPORT_EXTENSIONS = REPORTS_AND_FILES.values.flat_map { |val| val[:extensions] }.uniq

copy_from = []
no_push = false
regenerate_reports = false

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: continuous_reporting.rb [options]
        Specify directories with -d to add new test results and reports.
        Currently-known data will be indexed and git-pushed.
    BANNER

    opts.on("-d DIR", "Data dir for copying data and report files (may be specified multiple times)") do |dir|
        copy_from << dir
    end

    opts.on("-n", "--no-push", "Don't push the new Git commit, just create it locally") do
        no_push = true
    end

    opts.on("-r", "--regenerate-reports", "Don't use existing reports, generate them again") do
        regenerate_reports = true
    end
end.parse!

# Clone YJIT repo on "pages" branch, updated to latest version
YJITMetrics.clone_repo_with path: YJIT_METRICS_DIR, git_url: YJIT_METRICS_GIT_URL, git_branch: YJIT_METRICS_PAGES_BRANCH
#Dir.chdir(YJIT_METRICS_DIR) { YJITMetrics.check_call "git clean -d -f" }

# Copy JSON and report files into the branch
copy_from.each do |dir_to_copy|
    Dir.chdir(dir_to_copy) do
        # Copy raw data files to a place we can link them rather than include them in pages
        Dir["*.json"].each do |filename|
            FileUtils.cp(filename, File.join(YJIT_METRICS_DIR, "raw_benchmark_data/#{filename}"))
        end

        # Copy html, svg etc. to somewhere we can include them in other Jekyll pages
        REPORT_EXTENSIONS.each do |ext|
            Dir["*.#{ext}"].each do |filename|
                FileUtils.cp(filename, File.join(YJIT_METRICS_DIR, "_includes/reports/#{filename}"))
            end
        end
    end
end

# From here on out, we're just in the yjit-metrics checkout of "pages"
Dir.chdir(YJIT_METRICS_DIR)

starting_sha = YJITMetrics.check_output "git rev-list -n 1 HEAD".chomp

# Turn JSON files into reports where outdated - first, find out what test results we have
json_timestamps = {}
Dir["*_basic_benchmark_*.json", base: "raw_benchmark_data"].each do |filename|
    unless filename =~ /^(.*)_basic_benchmark_/
        raise "Problem parsing test-result filename #{filename.inspect}!"
    end
    ts = $1
    json_timestamps[ts] ||= []
    json_timestamps[ts] << filename
end

# Now see what reports we already have, so we can run anything missing.
report_timestamps = {}

report_files = Dir["*", base: "reports"].to_a
REPORTS_AND_FILES.each do |report_name, details|
    this_report_files = report_files.select { |filename| filename.include?(report_name) }
    this_report_files.each do |filename|
        unless filename =~ /(.*)_(\d{4}-\d{2}-\d{2}-\d{6}).([a-zA-Z]+)/
            raise "Couldn't parse filename #{filename.inspect} when generating reports!"
        end
        report_name_in_file = $1
        raise "Non-matching report name with filename, #{report_name.inspect} vs #{report_name_in_file.inspect}!" unless report_name == report_name_in_file
        ts = $2
        ext = $3

        report_timestamps[ts] ||= {}
        report_timestamps[ts][report_name] ||= []
        report_timestamps[ts][report_name].push filename
    end
end

# For now we only have one kind of report (share_speed), and we check for that.
json_timestamps.each do |ts, test_files|
    REPORTS_AND_FILES.each do |report_name, details|
        # Do we re-run this report? Yes, if we're re-running all reports or we can't find all the normal generated files.
        run_report = regenerate_reports ||
            !report_timestamps[ts] ||
            !report_timestamps[ts][report_name] ||
            report_timestamps[ts][report_name].size != details[:extensions].size

        # If the HTML report doesn't already exist, build it.
        if run_report
            files_for_report = test_files.map { |f| "raw_benchmark_data/#{f}" }
            puts "Running basic_report for timestamp #{ts} with data files #{files_for_report.inspect}"
            YJITMetrics.check_call("ruby ../yjit-metrics/basic_report.rb -d raw_benchmark_data --report=#{report_name} -o _includes/reports -w #{files_for_report.join(" ")}")

            report_filenames = details[:extensions].map { |ext| "_includes/reports/#{report_name}_#{ts}.#{ext}" }
            files_not_found = report_filenames.select { |f| !File.exist? f }

            unless files_not_found.empty?
                raise "We tried to create the report file(s) #{files_not_found.inspect} but failed! No process error, but the file(s) didn't appear."
            end

            report_timestamps[ts] ||= {}
            report_timestamps[ts][report_name] = report_filenames
        end

        # Now make sure we have a _benchmarks Jekyll entry for the dataset
        test_results_by_config = {}
        # Try to keep the iteration order stable with sort - we do *not* want this to autogenerate differently
        # every time and have massive Git churn. This lists out the test-result JSON files for this config and timestamp.
        json_timestamps[ts].sort.each do |file|
            unless file =~ /basic_benchmark_(.*).json$/
                raise "Error parsing JSON filename #{file.inspect}!"
            end
            config = $1
            test_results_by_config[config] = "raw_benchmark_data/#{file}"
        end

        generated_reports = {}
        REPORTS_AND_FILES.each do |report_name, details|
            details[:extensions].each do |ext|
                # Don't include the leading "_includes" - Jekyll checks there by default.
                generated_reports[report_name + "_" + ext] = "reports/#{report_name}_#{ts}.#{ext}"
            end
        end

        year, month, day, tm = ts.split("-")
        date_str = "#{year}-#{month}-#{day}"
        time_str = "#{tm[0..1]}:#{tm[2..3]}:#{tm[4..5]}"

        bench_data = {
            "layout" => "benchmark_details",
            "date_str" => date_str,
            "time_str" => time_str,
            "timestamp" => ts,
            "test_results" => test_results_by_config,
            "reports" => generated_reports,
        }

        # Finally write out the _benchmarks file for Jekyll to use.
        File.open("_benchmarks/bench_#{ts}.md", "w") do |f|
            f.print(YAML.dump(bench_data))
            f.print "\n---\n"
            f.print "Autogenerated by continuous_reporting.rb script."
            f.print "\n"
        end
    end
end

# Make sure it builds locally
YJITMetrics.check_call "bundle"  # Make sure all gems are installed
YJITMetrics.check_call "bundle exec jekyll build"
puts "Jekyll seems to build correctly. That means that GHPages should do the right thing on push."

# Commit if there is something to commit
diffs = (YJITMetrics.check_output "git status --porcelain").chomp
if diffs == ""
    puts "No changes found. Not committing or pushing."
elsif no_push
    puts "Changes found, but --no-push was specified. Not committing or pushing."
else
    puts "Changes found. Committing and pushing."
    YJITMetrics.check_call "git add reports _benchmarks"
    YJITMetrics.check_call 'git commit -m "Update reports via continuous_reporting.rb script"'
    YJITMetrics.check_call "git push"
end

puts "Finished continuous_reporting successfully!"
