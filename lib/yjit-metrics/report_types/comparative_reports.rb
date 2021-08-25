require_relative "yjit_stats_reports"

class YJITMetrics::CompareReport < YJITMetrics::YJITStatsReport
    def exactly_one_config_with_name(configs, substring, description)
        matching_configs = configs.select { |name| name.include?(substring) }
        raise "We found more than one candidate #{description} config (#{matching_configs.inspect}) in this result set!" if matching_configs.size > 1
        raise "We didn't find any #{description} config among #{configs.inspect}!" if matching_configs.empty?
        matching_configs[0]
    end

    def look_up_data_by_ruby(in_runs: false, no_jit: true, truffle: false)
        @with_yjit_config = exactly_one_config_with_name(@config_names, "with_yjit", "with-YJIT")
        @with_mjit_config = exactly_one_config_with_name(@config_names, "with_mjit", "with-MJIT")
        @no_jit_config    = exactly_one_config_with_name(@config_names, "no_jit", "no-JIT") if no_jit
        @truffle_config   = exactly_one_config_with_name(@config_names, "truffleruby", "Truffle") if truffle

        @configs_with_human_names = [
            ["YJIT", @with_yjit_config],
            ["MJIT", @with_mjit_config],
        ]
        @configs_with_human_names.push(["Truffle", @truffle_config]) if truffle
        @configs_with_human_names.push(["No JIT", @no_jit_config]) if no_jit

        # Grab relevant data from the ResultSet
        @times_by_config = {}
        [ @with_yjit_config, @with_mjit_config, @no_jit_config, @truffle_config ].compact.each do|config|
            @times_by_config[config] = @result_set.times_for_config_by_benchmark(config, in_runs: in_runs)
        end
        @yjit_stats = @result_set.yjit_stats_for_config_by_benchmark(@stats_config, in_runs: in_runs)

        @benchmark_names = filter_benchmark_names(@times_by_config[@with_yjit_config].keys)

        @times_by_config.each do |config_name, config_results|
            if config_results.nil? || config_results.empty?
                raise("No results for configuration #{config_name.inspect} in #{self.class}!")
            end
            no_result_benchmarks = @benchmark_names.select { |bench_name| config_results[bench_name].nil? || config_results[bench_name].empty? }
            unless no_result_benchmarks.empty?
                raise("No results in config #{config_name.inspect} for benchmark(s) #{no_result_benchmarks.inspect} in #{self.class}!")
            end
        end
    end

end

# This report is to compare YJIT's time-in-JIT versus its speedup for various benchmarks.
class YJITMetrics::CompareSpeedReport < YJITMetrics::CompareReport
    def self.report_name
        "compare_speed"
    end

    def initialize(config_names, results, benchmarks: [])
        # Set up the YJIT stats parent class
        super

        look_up_data_by_ruby(no_jit: true, truffle: true)

        no_stats_benchmarks = @benchmark_names.select { |bench_name| !@yjit_stats[bench_name] || !@yjit_stats[bench_name][0] || @yjit_stats[bench_name][0].empty? }
        unless no_stats_benchmarks.empty?
            raise "No YJIT stats found for benchmarks: #{no_stats_benchmarks.inspect}"
        end

        # Sort benchmarks by compiled ISEQ count
        @benchmark_names.sort_by! { |bench_name| @yjit_stats[bench_name][0]["compiled_iseq_count"] }

        @headings = [ "bench" ] +
            @configs_with_human_names.flat_map { |name, config| [ "#{name} (ms)", "#{name} RSD" ] } +
            @configs_with_human_names.flat_map { |name, config| config == @no_jit_config ? [] : [ "#{name} spd", "#{name} spd RSD" ] } +
            [ "% in YJIT" ]
        # Col formats are only used when formatting a text table, not for HTML or CSV
        @col_formats = [ "%s" ] +                                           # Benchmark name
            [ "%.1f", "%.2f%%" ] * @configs_with_human_names.size +         # Mean and RSD per-Ruby
            [ "%.2fx", "%.2f%%" ] * (@configs_with_human_names.size - 1) +  # Speedups per-Ruby
            [ "%.2f%%" ]                                                    # YJIT ratio

        @mean_by_config = {
            @no_jit_config => [],
            @with_mjit_config => [],
            @with_yjit_config => [],
            @truffle_config => [],
        }
        @rsd_by_config = {
            @no_jit_config => [],
            @with_mjit_config => [],
            @with_yjit_config => [],
            @truffle_config => [],
        }
        @speedup_by_config = {
            @with_mjit_config => [],
            @with_yjit_config => [],
            @truffle_config => [],
        }
        @yjit_ratio = []

        @benchmark_names.each do |benchmark_name|
            @configs_with_human_names.each do |name, config|
                this_config_times = @times_by_config[config][benchmark_name]
                this_config_mean = mean(this_config_times)
                @mean_by_config[config].push this_config_mean
                this_config_rel_stddev_pct = rel_stddev_pct(this_config_times)
                @rsd_by_config[config].push this_config_rel_stddev_pct
            end

            no_jit_mean = @mean_by_config[@no_jit_config][-1] # Last pushed -- the one for this benchmark
            no_jit_rel_stddev = @rsd_by_config[@no_jit_config][-1]
            @configs_with_human_names.each do |name, config|
                next if config == @no_jit_config

                this_config_mean = @mean_by_config[config][-1]
                this_config_rel_stddev = @rsd_by_config[config][-1]
                speed_ratio = no_jit_mean / this_config_mean
                speed_rel_stddev = Math.sqrt(no_jit_rel_stddev * no_jit_rel_stddev + this_config_rel_stddev * this_config_rel_stddev)
                @speedup_by_config[config].push [ speed_ratio, speed_rel_stddev ]
            end

            # A benchmark run may well return multiple sets of YJIT stats per benchmark name/type.
            # For these calculations we just add all relevant counters together.
            this_bench_stats = combined_stats_data_for_benchmarks([benchmark_name])

            total_exits = total_exit_count(this_bench_stats)
            retired_in_yjit = this_bench_stats["exec_instruction"] - total_exits
            total_insns_count = retired_in_yjit + this_bench_stats["vm_insns_count"]
            yjit_ratio_pct = 100.0 * retired_in_yjit.to_f / total_insns_count
            @yjit_ratio.push yjit_ratio_pct
        end
    end

    def report_table_data
        @benchmark_names.map.with_index do |bench_name, idx|
            [ bench_name ] +
                @configs_with_human_names.flat_map { |name, config| [ @mean_by_config[config][idx], @rsd_by_config[config][idx] ] } +
                @configs_with_human_names.flat_map { |name, config| config == @no_jit_config ? [] : @speedup_by_config[config][idx] } +
                [ @yjit_ratio[idx] ]
        end
    end

    def to_s
        format_as_table(@headings, @col_formats, report_table_data) +
            "\nRSD is relative standard deviation (stddev / mean), expressed as a percent.\n" +
            "Spd is the speed (iters/second) of the optimised implementation -- 2.0x would be twice as many iters per second.\n"
    end

    def write_file(filename)
        # If we render a comparative report to file, we need victor for SVG output.
        require "victor"

        svg = Victor::SVG.new template: :minimal
        # ...
        @svg_body = svg.render

        script_template = ERB.new File.read(__dir__ + "/../report_templates/compare_speed.html.erb")
        html_output = script_template.result(binding) # Evaluate an Erb template with template_settings
        File.open(filename + ".html", "w") { |f| f.write(html_output) }

        write_to_csv(filename + ".csv", [@headings] + report_table_data)
    end

end
