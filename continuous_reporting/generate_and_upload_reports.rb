#!/usr/bin/env ruby

require "json"
require "yaml"
require "fileutils"
require "optparse"
require "rbconfig"

require_relative "../lib/yjit_metrics"

### Required repos, etc, to build from

YM_REPO = YJITMetrics::ContinuousReporting::YM_REPO
RAW_BENCHMARK_ROOT = YJITMetrics::ContinuousReporting::RAW_BENCHMARK_ROOT
BUILT_REPORTS_ROOT = YJITMetrics::ContinuousReporting::BUILT_REPORTS_ROOT
GHPAGES_REPO = YJITMetrics::ContinuousReporting::GHPAGES_REPO

[RAW_BENCHMARK_ROOT, BUILT_REPORTS_ROOT].each do |dir|
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
        extensions: [ "html", "svg", "head.svg", "back.svg", "micro.svg", "csv" ],
    },
    "blog_memory_details" => {
        report_type: :basic_report,
        extensions: [ "html", "svg", "head.svg", "back.svg", "micro.svg", "csv" ],
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
        extensions: [ "bench_list.txt" ], # Funny thing here - we generate a *lot* of exit report files, but rarely with a fixed name.
    },
    "iteration_count" => {
        report_type: :basic_report,
        extensions: [ "html" ],
    },

    "blog_timeline" => {
        report_type: :timeline_report,
        extensions: [ "html" ],
    },
    "benchmark_timeline" => {
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
def basic_report_filenames(report_name, ts, prefix: "#{BUILT_REPORTS_ROOT}/_includes/reports/")
    exts = REPORTS_AND_FILES[report_name][:extensions]

    exts.map { |ext| "#{prefix}#{report_name}_#{ts}.#{ext}" }
end

def ruby_version_from_metadata(metadata)
  return unless metadata

  if (match = metadata["RUBY_DESCRIPTION"]&.match(/^(?:ruby\s+)?([0-9.]+\S*)/))
    match[1]
  else
    metadata["RUBY_VERSION"]
  end
end

no_push = false
regenerate_reports = false
regenerate_year = nil
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

    opts.on("-ry YEAR", "--regenerate-year YEAR", "Regenerate reports for a specific year") do |year|
        regenerate_year = year
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

# This is probably unnecessary now.
Dir.chdir(YM_REPO)
puts "Switched to #{Dir.pwd}"

# Find all the benchmark json file names we have from all time (but don't read the files yet).
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
# This looks in the report cache dir to see what file names exist
# so we can compare that to the list of file names we expect to exist.
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

        report_timestamps[ts] ||= {}
        report_timestamps[ts][report_name] ||= []
        report_timestamps[ts][report_name].push "#{BUILT_REPORTS_ROOT}/_includes/reports/#{filename}"
    end
end

# Check timestamped raw data versus the expected set of reports each basic_report can generate.
# Generate any basic reports that need it.
timestamps = json_timestamps.keys.sort
timestamps.each do |ts|
    test_files = json_timestamps[ts]
  if ENV['ALLOW_ARM_ONLY_REPORTS'] != '1'
    next unless test_files.any? { |tf| tf.include?("x86") } # Right now, ARM-only reports are very buggy.
  end
    do_regenerate_year = regenerate_year && ts.start_with?(regenerate_year)

    REPORTS_AND_FILES.each do |report_name, details|
        next unless details[:report_type] == :basic_report

        required_files = basic_report_filenames(report_name, ts)
        missing_files = required_files - ((report_timestamps[ts] || {})[report_name] || [])
        not_really_missing = missing_files.select { |filename| File.exist?(filename) }
        unless not_really_missing.empty?
            raise "Fake-missing files (internal error): #{not_really_missing.inspect}!"
        end

        # We want to re-run reports if:
        # - configured to re-run all (or this year)
        # - missing any expected generated files
        # - the data files have been updated more recently than the generated files (within a short recent timespan to avoid issues with old file formats)
        data_timestamp = File.mtime(File.join(RAW_BENCHMARK_ROOT, json_timestamps[ts].last))
        data_update_window = Time.now - 86400 * 7
        run_report = regenerate_reports ||
            do_regenerate_year  ||
            !((required_files - (report_timestamps.dig(ts, report_name) || [])).empty?) ||
            (ts.to_i >= 2024 && data_timestamp > data_update_window && data_timestamp > File.mtime(report_timestamps[ts][report_name].first))

        if run_report && die_on_regenerate
            puts "Report: #{report_name.inspect}, ts: #{ts.inspect}"
            puts "Available files: #{report_timestamps[ts][report_name].inspect}"
            puts "Required files: #{required_files.inspect}"
            raise "Regenerating reports isn't allowed! Failing on report #{report_name.inspect} for timestamp #{ts} with files #{report_timestamps[ts][report_name].inspect}!"
        end

        # If the report output doesn't already exist, build it.
        if run_report
            reason = regenerate_reports ? "we're regenerating everything" : nil
            reason ||= do_regenerate_year ? "we're regenerating year #{regenerate_year}" : nil
            reason ||= "we're missing files: #{missing_files.inspect}"

            puts "Running basic_report for timestamp #{ts} because #{reason} with data files #{test_files.inspect}"
            YJITMetrics.check_call("#{RbConfig.ruby} #{YM_REPO}/basic_report.rb -d #{RAW_BENCHMARK_ROOT} --report=#{report_name} -o #{BUILT_REPORTS_ROOT}/_includes/reports -w #{test_files.join(" ")}")

            rf = basic_report_filenames(report_name, ts)
            files_not_found = rf.select { |f| !File.exist? f }

            unless files_not_found.empty?
                raise "We tried to create the report file(s) #{files_not_found.inspect} but failed! No process error, but (#{files_not_found.size}/#{rf.size}) of the file(s) didn't appear."
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

        prod_yjit_data_by_platform = 'prod_ruby_with_yjit'.then do |config|
          YJITMetrics::PLATFORMS.each_with_object({}) do |platform, hash|
            test_results_by_config["#{platform}_#{config}"]&.then do |file|
              hash[platform] = JSON.parse(File.read(File.expand_path(file, RAW_BENCHMARK_ROOT)))
            end
          end
        end
        prod_yjit_data = prod_yjit_data_by_platform["x86_64"] || prod_yjit_data_by_platform["aarch64"]

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
                    if File.exist?("#{BUILT_REPORTS_ROOT}/_includes/#{report_filename}")
                        platforms[platform] = true
                        generated_reports[report_name + "_" + platform + "_" + ext.gsub(".", "_")] = report_filename
                    end
                end
            end
        end

        year, month, day, tm = ts.split("-")
        date_str = "#{year}-#{month}-#{day}"
        time_str = "#{tm[0..1]}:#{tm[2..3]}:#{tm[4..5]} UTC"

        yjit_commit = prod_yjit_data&.fetch("ruby_metadata", nil)&.yield_self do |rm|
          rm.fetch("RUBY_REVISION") do
            rm["RUBY_DESCRIPTION"].match(/ ([0-9a-fA-F]{6,})\)/)[1]
          end
        end

        bench_data = {
            "layout" => "benchmark_details",
            "date_str" => date_str,
            "time_str" => time_str,
            "timestamp" => ts,
            "platforms" => platforms.keys,
            "test_results" => test_results_by_config,
            "reports" => generated_reports,
            "yjit_bench_commit" => prod_yjit_data&.dig("full_run", "git_versions", "yjit_bench"),
            "yjit_commit" => yjit_commit,
            "yjit_configure_args" => prod_yjit_data&.dig("ruby_metadata", "RbConfig configure_args"),
            "yjit_cc_version" => prod_yjit_data&.dig("ruby_metadata", "RbConfig CC_VERSION_MESSAGE")&.lines&.first&.strip,
            "yjit_ruby_version" => ruby_version_from_metadata(prod_yjit_data&.dig("ruby_metadata")),
            "yjit_ruby_description" => prod_yjit_data&.dig("ruby_metadata", "RUBY_DESCRIPTION"),
            "cpu_info" => prod_yjit_data_by_platform&.map { |k, v| [k, v.dig("ruby_metadata", "cpu info")] }.to_h,
            "duration" => prod_yjit_data_by_platform&.map { |k, v| [k, v.dig("extra", "total_bench_seconds")] }.to_h,
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
        YJITMetrics.check_call("#{RbConfig.ruby} #{YM_REPO}/timeline_report.rb -d #{RAW_BENCHMARK_ROOT} --report='#{timeline_reports.keys.join(",")}' -o #{BUILT_REPORTS_ROOT}")
    end

    # TODO: figure out a new way to verify that appropriate files were written. With various subdirs, the old way won't cut it.
end

YJITMetrics.check_call "bin/analysis --spacious #{RAW_BENCHMARK_ROOT} > #{BUILT_REPORTS_ROOT}/_includes/analysis.txt"

# Make sure it builds locally
YJITMetrics.check_call "site/exe build"

puts "Static site seems to build correctly. That means that GHPages should do the right thing on push."

# Copy built _site directory into raw pages repo as a new single commit, to branch new_pages
Dir.chdir GHPAGES_REPO
puts "Switched to #{Dir.pwd}"

# Currently this will only be true on the server.
if File.exist?(".git")
  remote = "origin"
  branch = "pages"

  YJITMetrics.check_call "git checkout #{branch}" # Should already be on this branch (no-op).
  # Get any changes from the remote.
  YJITMetrics.check_call "git fetch #{remote} #{branch} && git reset --hard #{remote}/#{branch}"

  YJITMetrics.check_call "rsync --exclude=.git -ar --ignore-times --delete #{YM_REPO}/site/_site/ ./"

  YJITMetrics.check_call "touch .nojekyll"
  YJITMetrics.check_call "git add ."
  if `git status --porcelain=1 --untracked-files=no | grep -E '^[A-Z]' | wc -l`.strip.to_i.nonzero?
    YJITMetrics.check_call "git commit -m 'Rebuilt site HTML'"
  else
    puts "No changes found"
  end

  unless no_push
    # Reset the pages branch to the new built site
    YJITMetrics.check_call "git push -f #{remote} #{branch}"
  end
end

printf "Reporting RSS: %dMB\n", `ps -p #{$$} -o rss=`.to_i / 1024

puts "Finished generate_and_upload_reports successfully in #{YM_REPO}!"
