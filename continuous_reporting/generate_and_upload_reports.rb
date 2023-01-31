#!/usr/bin/env ruby

require "json"
require "yaml"
require "fileutils"
require "optparse"

require_relative "../lib/yjit-metrics"

# Raw benchmark data gets written to a platform- and date-specific subdirectory, but will often be read from multiple subdirectories.
RAW_BENCHMARK_ROOT = "raw_benchmark_data"

def benchmark_file_out_path(filename)
    if filename =~ /^(.*)_basic_benchmark_(.*).json$/
        ts = $1
        config = $2

        config_platform = YJITMetrics::PLATFORMS.detect { |platform| config.start_with?(platform) }
        if !config_platform
            raise "Can't parse platform from config in filename: #{filename.inspect} / #{config.inspect}!"
        end

        year, month, day, tm = ts.split("-")
        if ts == "" || year == "" || day == ""
            raise "Empty string when parsing timestamp: #{ts.inspect}!"
        end
        "#{RAW_BENCHMARK_ROOT}/#{config_platform}/#{year}-#{month}/#{ts}_basic_benchmark_#{config}.json"
    else
        raise "Can't parse filename: #{filename}!"
    end
end

# TODO: load the extensions out of the class objects
REPORTS_AND_FILES = {
    "blog_speed_headline" => {
        report_type: :basic_report,
        extensions: [ "html" ],
    },
    "blog_speed_details" => {
        report_type: :basic_report,
        extensions: [ "html", "raw_details.html", "svg", "head.svg", "back.svg", "micro.svg", "tripwires.json", "csv" ],
    },
    "blog_memory_details" => {
        report_type: :basic_report,
        extensions: [ "html" ],
    },
    "blog_yjit_stats" => {
        report_type: :basic_report,
        extensions: [ "html" ],
    },
    "variable_warmup" => {
        report_type: :basic_report,
        extensions: [ "warmup_settings.json" ],
    },
    "blog_exit_reports" => {
        report_type: :basic_report,
        extensions: [ "bench_list.html" ], # Funny thing here - we generate a *lot* of exit report files, but rarely with a fixed name.
    },
    "iteration_count" => {
        report_type: :basic_report,
        extensions: [ "html" ],
    },

    "blog_timeline" => {
        report_type: :timeline_report,
        extensions: [ "html" ],
    },
    "mini_timelines" => {
        report_type: :timeline_report,
        extensions: [ "html" ],
    },
    "yjit_stats_timeline" => {
        report_type: :timeline_report,
        extensions: [ "html" ],
    },
}

# Note: we use extensions *directly* for timeline reports, and they don't use timestamps.
# So this is only for basic reports.
def report_filenames(report_name, ts, prefix: "_includes/reports/")
    exts = REPORTS_AND_FILES[report_name][:extensions]

    exts.map { |ext| "#{prefix}#{report_name}_#{ts}.#{ext}" }
end

copy_from = []
no_push = false
regenerate_reports = false
die_on_regenerate = false
only_reports = nil

OptionParser.new do |opts|
    opts.banner = <<~BANNER
      Usage: generate_and_upload_reports.rb [options]
        Specify directories with -d to add new test results and reports.
        Currently-known data will be indexed and git-pushed.
    BANNER

    opts.on("-d DIR", "Copy raw data and report files out of this directory (may be specified multiple times)") do |dir|
        copy_from << dir
    end

    opts.on("-n", "--no-push", "Don't push the new Git commit, just modify files locally") do
        no_push = true
    end

    opts.on("-r", "--regenerate-reports", "Don't use existing reports, generate them again") do
        regenerate_reports = true
    end

    opts.on("-p", "--prevent-regenerate", "Fail if reports would be regenerated") do
        die_on_regenerate = true
    end

    opts.on("-o REPORTS", "--only-reports REPORTS", "Only run this specific set of reports") do |reports|
        only_reports = reports.split(",").map(&:strip)
    end
end.parse!

if only_reports
    bad_report_names = only_reports - REPORTS_AND_FILES.keys
    raise("Unknown report names: #{bad_report_names.inspect} not found in #{REPORTS_AND_FILES.keys.inspect}!") unless bad_report_names.empty?
    REPORTS_AND_FILES.select! { |k, _| only_reports.include?(k) }
end

# If want to check into the repo and file issues, we need credentials.
YJIT_METRICS_PAGES_DIR = File.expand_path File.join(__dir__, "../../yjit-metrics-pages")
github_token = ENV["BENCHMARK_CI_GITHUB_TOKEN"] ? ENV["BENCHMARK_CI_GITHUB_TOKEN"].chomp : nil

if no_push && !File.exist?(YJIT_METRICS_PAGES_DIR)
    raise "This script expects to be cloned in a repo right next to a \"yjit-metrics-pages\" repo of the `pages` branch of yjit-metrics"
end

unless github_token || no_push
    # Unless the token is set explicitly, we hope and expect that it will be part of the URL in the
    # pages repository, so "git push" just works. So we'll read it from there.

    git_config = File.join(YJIT_METRICS_PAGES_DIR, ".git", "config")
    if File.exist?(git_config)
        contents = File.read(git_config)
        before, after = contents.split('[remote "origin"]', 2)
        if after
            if after =~ /url = https:\/\/([^@]+)@github\.com/
                github_token = $1
            else
                puts "Content that was unparseable: #{after.inspect}"
                puts "Found .git/config, but couldn't parse git URL with token from remote 'origin'!"
            end
        else
            puts "Found .git/config, but couldn't find remote origin inside it!"
        end
    else
        puts "Looking for .git/config in #{git_config.inspect}, but can't find it to load token!"
    end

    unless github_token
        raise "Please set BENCHMARK_CI_GITHUB_TOKEN to an appropriate GitHub token if you need to push results or use --no-push"
    end
end

GITHUB_TOKEN = github_token

# This script expects to be cloned in a repo right next to a "yjit-metrics-pages" repo for the Github Pages branch of yjit-metrics
YJIT_METRICS_GIT_URL = GITHUB_TOKEN ? "https://#{GITHUB_TOKEN}@github.com/Shopify/yjit-metrics.git" : "https://github.com/Shopify/yjit-metrics.git"
YJIT_METRICS_PAGES_BRANCH = "pages"

# Clone YJIT repo on "pages" branch, updated to latest version
YJITMetrics.clone_repo_with path: YJIT_METRICS_PAGES_DIR, git_url: YJIT_METRICS_GIT_URL, git_branch: YJIT_METRICS_PAGES_BRANCH, do_clean: false
if GITHUB_TOKEN
  Dir.chdir(YJIT_METRICS_PAGES_DIR) do
    system("git pull") or raise("Error trying to git pull in pages dir!") # use check_call
  end
end

# We don't normally want to clean this directory - sometimes we run with --no-push, and this would destroy those results.
#Dir.chdir(YJIT_METRICS_PAGES_DIR) { YJITMetrics.check_call "git clean -d -f" }

# Copy JSON and report files into the branch
copy_from.each do |dir_to_copy|
    Dir.chdir(dir_to_copy) do
        # Copy raw data files to a place we can link them rather than include them in pages
        Dir["*_basic_benchmark_*.json"].each do |filename|
            out_file = benchmark_file_out_path(filename)
            dir = File.join(YJIT_METRICS_PAGES_DIR, File.dirname(out_file))
            FileUtils.mkdir_p dir
            FileUtils.cp(filename, File.join(YJIT_METRICS_PAGES_DIR, out_file))
            puts "Copying data file: #{filename.inspect} to #{out_file.inspect} in dir #{dir.inspect}"
        end

        # We used to copy report files from the data dir. We probably shouldn't.

        # Copy report files to somewhere we can include them in other Jekyll pages
        #REPORTS_AND_FILES.keys.each do |report_name|
        #    Dir["#{report_name}_*\.([^.]+)"].each do |filename|
        #        ext = $1
        #        if REPORTS_AND_FILES[report_name][:extensions].include?(ext)
        #            FileUtils.cp(filename, File.join(YJIT_METRICS_PAGES_DIR, "_includes/reports/#{filename}"))
        #        end
        #    end
        #end
    end
end

# From here on out, we're just in the yjit-metrics checkout of "pages"
Dir.chdir(YJIT_METRICS_PAGES_DIR)

starting_sha = YJITMetrics.check_output "git rev-list -n 1 HEAD".chomp

# Turn JSON files into reports where outdated - first, find out what test results we have.
# json_timestamps maps timestamps to file paths relative to the RAW_BENCHMARK_ROOT
json_timestamps = {}
Dir["**/*_basic_benchmark_*.json", base: RAW_BENCHMARK_ROOT].each do |filename|
    unless filename =~ /^((.*)\/)?(.*)_basic_benchmark_/
        raise "Problem parsing test-result filename #{filename.inspect}!"
    end
    ts = $3
    json_timestamps[ts] ||= []
    json_timestamps[ts] << filename
end

# Now see what reports we already have, so we can run anything missing.
report_timestamps = {}
report_files = Dir["*", base: "_includes/reports"].to_a
REPORTS_AND_FILES.each do |report_name, details|
    next unless details[:report_type] == :basic_report # Timeline reports don't produce a series of timestamped files
    this_report_files = report_files.select { |filename| filename.include?(report_name) }
    this_report_files.each do |filename|
        unless filename =~ /(.*)_(\d{4}-\d{2}-\d{2}-\d{6}).([a-zA-Z_0-9]+)/
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

# Check timestamped raw data versus the expected set of reports each basic_report can generate.
# Generate any basic reports that need it.
json_timestamps.each do |ts, test_files|
    REPORTS_AND_FILES.each do |report_name, details|
        next unless details[:report_type] == :basic_report

        required_files = report_filenames(report_name, ts, prefix: "")
        missing_files = required_files - ((report_timestamps[ts] || {})[report_name] || [])

        # Do we re-run this report? Yes, if we're re-running all reports or we can't find all the generated files.
        run_report = regenerate_reports ||
            !report_timestamps[ts] ||
            !report_timestamps[ts][report_name] ||
            !((required_files - report_timestamps[ts][report_name]).empty?)

        if run_report && die_on_regenerate
            puts "Report: #{report_name.inspect}, ts: #{ts.inspect}"
            puts "Available files: #{report_timestamps[ts][report_name].inspect}"
            puts "Required files: #{required_files.inspect}"
            raise "Regenerating reports isn't allowed! Failing on report #{report_name.inspect} for timestamp #{ts} with files #{report_timestamps[ts][report_name].inspect}!"
        end

        # If the report output doesn't already exist, build it.
        if run_report
            reason = regenerate_reports ? "we're regenerating everything" : "we're missing files: #{missing_files.inspect}"

            puts "Running basic_report for timestamp #{ts} because #{reason} with data files #{test_files.inspect}"
            YJITMetrics.check_call("ruby ../yjit-metrics/basic_report.rb -d #{RAW_BENCHMARK_ROOT} --report=#{report_name} -o _includes/reports -w #{test_files.join(" ")}")

            rf = report_filenames(report_name, ts)
            files_not_found = rf.select { |f| !File.exist? f }

            unless files_not_found.empty?
                raise "We tried to create the report file(s) #{files_not_found.inspect} but failed! No process error, but the file(s) didn't appear."
            end

            report_timestamps[ts] ||= {}
            report_timestamps[ts][report_name] = rf
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
            test_results_by_config[config] = File.join(RAW_BENCHMARK_ROOT, file)
        end

        generated_reports = {}
        platforms = {}
        REPORTS_AND_FILES.each do |report_name, details|
            next unless details[:report_type] == :basic_report

            # Add a field like blog_speed_details_svg
            details[:extensions].each do |ext|
                # Don't include the leading "_includes" - Jekyll checks there by default.
                generated_reports[report_name + "_" + ext.gsub(".", "_")] = "reports/#{report_name}_#{ts}.#{ext}"

                # Add a field like blog_speed_details_x86_64_svg
                YJITMetrics::PLATFORMS.each do |platform|
                    report_filename = "reports/#{report_name}_#{ts}.#{platform}.#{ext}"
                    if File.exist?("_includes/#{report_filename}")
                        platforms[platform] = true
                        generated_reports[report_name + "_" + platform + "_" + ext.gsub(".", "_")] = report_filename
                    end
                end
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
            "platforms" => platforms.keys,
            "test_results" => test_results_by_config,
            "reports" => generated_reports,
        }

        contents = YAML.dump(bench_data) + "\n---\nAutogenerated by continuous_reporting/generate_and_upload_reports.rb script.\n"
        filename = "_benchmarks/bench_#{ts}.md"
        # Only write the file if contents don't match - we don't want to re-run Jekyll for non-changes
        if !File.exist?(filename) || File.read(filename) != contents
            # Write out the _benchmarks file for Jekyll to use.
            File.open(filename, "w") { |f| f.write(contents) }
        end
    end
end

# Now that we've handled all the point-in-time reports from basic_report, we'll
# run any all-time (a.k.a. timeline) reports.
# We re-run the timeline report unless we've been told to prevent regenerating completely.
unless die_on_regenerate
    timeline_reports = REPORTS_AND_FILES.select { |report_name, details| details[:report_type] == :timeline_report }

    # It's possible to run only specific non-timeline reports -- then this would be empty.
    unless timeline_reports.empty?
        YJITMetrics.check_call("ruby ../yjit-metrics/timeline_report.rb -d #{RAW_BENCHMARK_ROOT} --report='#{timeline_reports.keys.join(",")}' -o .")
    end

    # TODO: figure out a new way to verify that appropriate files were written. With various subdirs, the old way won't cut it.
end

# Make sure it builds locally
YJITMetrics.check_call "bundle"  # Make sure all gems are installed
YJITMetrics.check_call "bundle exec jekyll build"
puts "Jekyll seems to build correctly. That means that GHPages should do the right thing on push."

dirs_to_commit = [ "_benchmarks", "_includes", RAW_BENCHMARK_ROOT, "reports" ]

# Commit if there is something to commit
diffs = (YJITMetrics.check_output "git status --porcelain #{dirs_to_commit.join(" ")}").chomp
if diffs == ""
    puts "No changes found. Not committing or pushing."
elsif no_push
    puts "Changes found, but --no-push was specified. Not committing or pushing."
else
    puts "Changes found. Committing and pushing."
    YJITMetrics.check_call "git add #{dirs_to_commit.join(" ")}"
    YJITMetrics.check_call 'git commit -m "Update reports via continuous_reporting.rb script"'
    YJITMetrics.check_call "git push"
end

puts "Finished generate_and_upload_reports successfully!"
