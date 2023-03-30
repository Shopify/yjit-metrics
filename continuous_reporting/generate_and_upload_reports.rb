#!/usr/bin/env ruby

require "json"
require "yaml"
require "fileutils"
require "optparse"

require_relative "../lib/yjit-metrics"

### Required repos, etc, to build from

# Dir in which yjit-metrics, yjit-bench, etc are cloned
YM_ROOT_DIR = File.expand_path(File.join(__dir__, "../.."))

# Clone of yjit-metrics repo, pages branch
YJIT_METRICS_PAGES_DIR = File.expand_path File.join(YM_ROOT_DIR, "yjit-metrics-pages")

# Raw benchmark data gets written to a platform- and date-specific subdirectory, but will often be read from multiple subdirectories
RAW_BENCHMARK_ROOT = File.join(YM_ROOT_DIR, "raw-benchmark-data")

# This contains Jekyll source files of various kinds - everything but the built reports
RAW_REPORTS_ROOT = File.join(YM_ROOT_DIR, "raw-yjit-reports")

# We cache all the built per-run reports, which can take a long time to rebuild
BUILT_REPORTS_ROOT = File.join(YM_ROOT_DIR, "built-yjit-reports")

[YJIT_METRICS_PAGES_DIR, RAW_BENCHMARK_ROOT, RAW_REPORTS_ROOT, BUILT_REPORTS_ROOT].each do |dir|
  unless File.exist?(dir)
    raise "We expected directory #{dir.inspect} to exist in order to generate reports!"
  end
end

# mkdir output directories
FileUtils.mkdir_p "#{BUILT_REPORTS_ROOT}/_includes/reports"
FileUtils.mkdir_p "#{BUILT_REPORTS_ROOT}/_benchmarks"
FileUtils.mkdir_p "#{BUILT_REPORTS_ROOT}/reports/timeline"

### Per-run reports to build

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
    "memory_timeline" => {
        report_type: :timeline_report,
        extensions: [ "html" ],
    },
}

# Timeline reports don't have a timestamp in the filename.
# So this is only for basic reports.
def report_filenames(report_name, ts, prefix: "_includes/reports/")
    exts = REPORTS_AND_FILES[report_name][:extensions]

    exts.map { |ext| "#{prefix}#{report_name}_#{ts}.#{ext}" }
end

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

# From here on out, we're just in the yjit-metrics checkout of "pages" -- until we can stop relying on it.
Dir.chdir(YJIT_METRICS_PAGES_DIR)
YJITMetrics.check_call("git checkout pages")

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
report_files = Dir["*", base: "#{BUILT_REPORTS_ROOT}/_includes/reports"].to_a
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
            YJITMetrics.check_call("ruby ../yjit-metrics/basic_report.rb -d #{RAW_BENCHMARK_ROOT} --report=#{report_name} -o #{BUILT_REPORTS_ROOT}/_includes/reports -w #{test_files.join(" ")}")

            rf = report_filenames(report_name, ts)
            files_not_found = rf.select { |f| !File.exist? f }

            unless files_not_found.empty?
                raise "We tried to create the report file(s) #{files_not_found.inspect} but failed! No process error, but the file(s) didn't appear."
            end

            report_timestamps[ts] ||= {}
            report_timestamps[ts][report_name] = rf
        end

        # Now make sure we have a _benchmarks entry for the dataset
        test_results_by_config = {}
        # Try to keep the iteration order stable with sort - we do *not* want this to autogenerate differently
        # every time and have massive Git churn. This lists out the test-result JSON files for this config and timestamp.
        json_timestamps[ts].sort.each do |file|
            unless file =~ /basic_benchmark_(.*).json$/
                raise "Error parsing JSON filename #{file.inspect}!"
            end
            config = $1
            test_results_by_config[config] = file
        end

        generated_reports = {}
        platforms = {}
        REPORTS_AND_FILES.each do |report_name, details|
            next unless details[:report_type] == :basic_report

            # Add a field like blog_speed_details_svg
            details[:extensions].each do |ext|
                # Don't include the leading "_includes"
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
        filename = "#{BUILT_REPORTS_ROOT}/_benchmarks/bench_#{ts}.md"
        # Only write the file if contents don't match - we don't want to re-run for non-changes
        if !File.exist?(filename) || File.read(filename) != contents
            # Write out the _benchmarks file.
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
        YJITMetrics.check_call("ruby ../yjit-metrics/timeline_report.rb -d #{RAW_BENCHMARK_ROOT} --report='#{timeline_reports.keys.join(",")}' -o #{BUILT_REPORTS_ROOT}")
    end

    # TODO: figure out a new way to verify that appropriate files were written. With various subdirs, the old way won't cut it.
end

# Switch to raw-yjit-reports, which symlinks to the built reports
Dir.chdir(RAW_REPORTS_ROOT)

# Make sure it builds locally
# Funny thing here - this picks up the Bundler config from this script, via env vars.
# So it's important to include the kramdown gem, and others used in reporting, in
# the yjit-metrics Gemfile. Or you can run generate_and_upload_reports.rb from the
# other directory, where it picks up the reporting Gemfile. That works too.
YJITMetrics.check_call "bundle exec ruby -I./_framework _framework/render.rb build"

puts "Static site seems to build correctly. That means that GHPages should do the right thing on push."

dirs_to_commit = [ "_benchmarks", "_includes", "reports" ]

## Commit if there is something to commit
#diffs = (YJITMetrics.check_output "git status --porcelain #{dirs_to_commit.join(" ")}").chomp
#if diffs == ""
#    puts "No changes found. Not committing or pushing."
#elsif no_push
#    puts "Changes found, but --no-push was specified. Not committing or pushing."
#else
#    puts "Changes found. Committing and pushing."
#    YJITMetrics.check_call "git add #{dirs_to_commit.join(" ")}"
#    YJITMetrics.check_call 'git commit -m "Update reports via continuous_reporting.rb script"'
#    YJITMetrics.check_call "git push"
#end

=begin
# Copy built _site directory into YJIT_METRICS_PAGES repo as a new single commit, to branch new_pages
Dir.chdir YJIT_METRICS_PAGES_DIR
YJITMetrics.check_call "git checkout --orphan -b new_pages && git rm -r * && cp -r #{RAW_REPORTS_ROOT}/_site/* . && git add ."
YJITMetrics.check_call "git commit -m 'Rebuilt site HTML' && git push -f"

# Reset the pages branch to the new built site
YJITMetrics.check_call "git checkout pages"
# TODO: UNCOMMENT WHEN WE'RE READY TO CHANGE OVER
#YJITMetrics.check_call "git checkout pages && git reset --hard new_pages && git push -f"
=end

puts "Finished generate_and_upload_reports successfully!"
