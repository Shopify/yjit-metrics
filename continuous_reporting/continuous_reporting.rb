#!/usr/bin/env ruby

require "json"
require "fileutils"
require "optparse"

require_relative "../lib/yjit-metrics"

# Slight subtlety: this repo is currently not public, so we need a token to pull or clone it.
raise "Please set YJIT_METRICS_GITHUB_TOKEN to an appropriate GitHub token!" unless ENV["YJIT_METRICS_GITHUB_TOKEN"]
GITHUB_TOKEN = ENV["YJIT_METRICS_GITHUB_TOKEN"].chomp
YJIT_METRICS_DIR = File.expand_path File.join(__dir__, "../../yjit-metrics-pages")
YJIT_METRICS_GIT_URL = "https://#{GITHUB_TOKEN}@github.com/Shopify/yjit-metrics.git"
YJIT_METRICS_PAGES_BRANCH = "pages"

copy_from = []

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: continuous_reporting.rb [options]
        Specify directories with -d to add new test results and reports.
        Currently-known data will be indexed and git-pushed.
    BANNER

    opts.on("-d DIR", "Data dir for copying data and report files (may be specified multiple times)") do |dir|
        copy_from << dir
    end
end.parse!

# Clone YJIT repo on "pages" branch, updated to latest version
YJITMetrics.clone_repo_with path: YJIT_METRICS_DIR, git_url: YJIT_METRICS_GIT_URL, git_branch: YJIT_METRICS_PAGES_BRANCH
Dir.chdir(YJIT_METRICS_DIR) { YJITMetrics.check_call "git clean -d -f" }

# Copy JSON and report files into the branch
copy_from.each do |dir_to_copy|
    Dir.chdir(dir_to_copy) do
        (Dir["*.json"].to_a + Dir["*.html"].to_a).each do |filename|
            FileUtils.cp(filename, File.join(YJIT_METRICS_DIR, "reports/#{filename}"))
        end
    end
end

# From here on out, we're just in the yjit-metrics checkout of "pages"
Dir.chdir(YJIT_METRICS_DIR)

starting_sha = YJITMetrics.check_output "git rev-list -n 1 HEAD".chomp

# Turn JSON files into reports where outdated - first, find out what test results we have
json_timestamps = {}
Dir["*_basic_benchmark_*.json", base: "reports"].each do |filename|
    unless filename =~ /^(.*)_basic_benchmark_/
        raise "Problem parsing test-result filename #{filename.inspect}!"
    end
    ts = $1
    json_timestamps[ts] ||= []
    json_timestamps[ts] << filename
end

report_timestamps = {}
Dir["share_speed_*.html", base: "reports"].each do |filename|
    unless filename =~ /share_speed_(.*)\.html$/
        raise "Problem parsing report filename #{filename.inspect}!"
    end

    ts = $1
    report_timestamps[ts] ||= []
    report_timestamps[ts] << filename
end

# For now we only have one kind of report (share_speed), and we check for that.
json_timestamps.each do |ts, test_files|
    if report_timestamps[ts] && !report_timestamps[ts].empty?
        # Great! We *should* have this report, and we *do* have this report.
    else
        report_files = test_files.map { |f| "reports/#{f}" }
        puts "Running basic_report for timestamp #{ts} with data files #{report_files.inspect}"
        YJITMetrics.check_call("ruby ../yjit-metrics/basic_report.rb -d reports --report=share_speed -o reports -w #{report_files.join(" ")}")

        report_filename = "reports/share_speed_#{ts}.html"
        unless File.exist?(report_filename)
            raise "We tried to create the report #{report_filename} but failed! No process error, but the file didn't appear."
        end
    end
end

# TODO: Rebuild higher-level index files - or do we do this in Jekyll?

# Make sure it builds locally
YJITMetrics.check_call "bundle"  # Make sure all gems are installed
YJITMetrics.check_call "bundle exec jekyll build"
puts "Jekyll seems to build correctly. That means that GHPages should do the right thing on push."

# Commit if there is something to commit
diffs = (YJITMetrics.check_output "git status --porcelain").chomp
unless diffs == ""
    YJITMetrics.check_call "git add reports"
    YJITMetrics.check_call 'git commit -m "Update reports via continuous_reporting.rb script"'
end

# Push all the new files (if any) to GitHub Pages
YJITMetrics.check_call "git push"

puts "Finished continuous_reporting successfully!"
