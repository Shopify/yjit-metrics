#!/usr/bin/env python3

import json
import argparse
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.ticker import StrMethodFormatter

# Sample commands:
# ./plot_benchmarks.py data/partial_warmup_data/2021-07-21-*_basic_benchmark_*

parser = argparse.ArgumentParser()
parser.add_argument('--bench_name')
parser.add_argument('--out_file', default='benchmarks.png')
parser.add_argument('input_files', nargs='*')
args = parser.parse_args()

# Mapping of Ruby engines to data for
bench_name_to_engine_results = {}

for filename in args.input_files:
    if 'yjit_stats' in filename:
        continue

    with open(filename) as f:
        data = json.load(f)

    times = data['times']

    # Hacky solution for now
    engine = None
    if 'yjit' in filename:
        engine = 'YJIT'
    elif 'mjit' in filename:
        engine = 'MJIT'
    elif 'truffle' in filename:
        engine = 'TruffleRuby'
    elif 'no_jit' in filename:
        engine = 'Interpreter'
    assert engine != None

    # Times is a single key / value pair.  The key is the benchmark name,
    # the value is an array with the amount of time spent for each run.  We
    # want a data structure that looks like this:
    # data = {  "psych-load" => {
    #               "YJIT"        => [x, x, x,],
    #               "MJIT"        => [x, x, x,],
    #               "Interpreter" => [x, x, x,],
    #           },
    #           "30k ifs" => ...
    #        }
    for bench_name, bench_values in times.items():
        engine_results = bench_name_to_engine_results.get(bench_name, {})

        # Find the results for this particular engine
        engine_result_times = engine_results.get(engine, [])
        engine_result_times += bench_values

        engine_results[engine] = engine_result_times
        bench_name_to_engine_results[bench_name] = engine_results

# Array of benchmark names
#benchmark_names = list(bench_name_to_engine_results.keys())
benchmark_names = [
    '30k_methods',
    '30k_ifelse',
    'optcarrot',
    'lee',
    'psych-load',
    'liquid-render',
    'activerecord',
    'railsbench'
]

# Make sure all benchmarks have the same number of samples
for bench_name, engine_results in bench_name_to_engine_results.items():
    sample_lengths = [len(l) for l in engine_results.values()]

    if len(np.unique(sample_lengths)) != 1:
        min_len = sorted(sample_lengths)[0]
        for results in engine_results.values():
            del results[min_len:]

# Arrays of yvalues and stddev for each engine
# One yvalue per benchmark
yvalues_per_engine = {}
stddev_per_engine = {}


# Normalize samples and add to the yvalues / stddev maps
for bench_name in benchmark_names:
    engine_results = bench_name_to_engine_results[bench_name]

    interp_mean = np.mean(engine_results["Interpreter"], axis=0)

    for engine_name, results in engine_results.items():
        mean = np.mean(results, axis=0)
        scaled_results = [r / interp_mean for r in results]
        scaled_stddev = np.std(scaled_results, axis=0)

        # Normalize results based on the interpreter mean
        val_list = yvalues_per_engine.get(engine_name, [])
        val_list.append(mean / interp_mean)
        yvalues_per_engine[engine_name] = val_list

        val_list = stddev_per_engine.get(engine_name, [])
        val_list.append(scaled_stddev)
        stddev_per_engine[engine_name] = val_list


# Generate the plot
fig = plt.figure()

fig, ax = plt.subplots()

x = np.arange(len(benchmark_names)) # the label locations
plt.xticks(rotation=45)
plt.ylabel("Execution time (s)")
ax.set_xticks(x)
ax.set_xticklabels(benchmark_names)


bar_width = 0.2

for engine_idx, engine in enumerate(yvalues_per_engine.keys()):

    y = yvalues_per_engine[engine]
    yerr = stddev_per_engine[engine]

    ax.bar(np.arange(len(y)) + engine_idx * bar_width, y, yerr=yerr, capsize=5, width=bar_width, label=engine)


plt.legend(loc='upper right')

fig.tight_layout()
plt.savefig(args.out_file, dpi=300)
