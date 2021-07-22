#!/usr/bin/env python3

import json
import argparse
import numpy as np
import matplotlib.pyplot as plt

# Sample commands:
# ./plot_warmup_bars.py --bench_name=psych-load data/partial_warmup_data/2021-07-21-*_basic_benchmark_*prod*
# ./plot_warmup_bars.py --bench_name=activerecord data/aws_long_run_warmups/*_basic_benchmark_*.json

parser = argparse.ArgumentParser()
parser.add_argument('--bench_name')
parser.add_argument('--out_file', default='plot.png')
parser.add_argument('input_files', nargs='*')
args = parser.parse_args()

# Mapping of Ruby engines to lists of time values
series_per_engine = {}

for filename in args.input_files:
    if 'yjit_stats' in filename:
        continue

    with open(filename) as f:
        data = json.load(f)

    times = data['times']
    if args.bench_name not in times:
        continue
    times = times[args.bench_name]

    print(filename)

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

    series = series_per_engine.get(engine, [])

    # Each line should have the same number of iterations
    if len(series) > 0:
        prev_times = series[-1]
    assert len(times) >= 2

    series.append(times)
    series_per_engine[engine] = series

yvalues_per_engine = {}
stddev_per_engine = {}

itrs_to_plot = [1, 10, 20, 100, 1000]
itrs_to_plot = list(map(lambda i: i-1, itrs_to_plot))

for engine, series in series_per_engine.items():
    num_series = len(series)
    max_itrs = max(map(lambda s: len(s), series))
    min_itrs = min(map(lambda s: len(s), series))
    print("engine {}, min_itrs {}, max_itrs {}".format(engine, min_itrs, max_itrs))

    # Limit series to the minimum length encountered
    series = map(lambda s: s[:min_itrs], series)

    tensor = np.zeros((num_series, min_itrs))

    for run_no, series in enumerate(series):
        tensor[run_no] = series

    # Compute the mean and stddev per iteration over all the runs
    mean = np.mean(tensor, axis=0)
    std = np.std(tensor, axis=0)

    # Extract out only the iterations to plot
    mean = mean[itrs_to_plot]
    std = std[itrs_to_plot]

    yvalues_per_engine[engine] = mean
    stddev_per_engine[engine] = std

    print(mean)

#
# Based on examples found at:
# https://pythonbasics.org/matplotlib-bar-chart/
# https://matplotlib.org/stable/gallery/lines_bars_and_markers/barchart.html
#

# Generate the plot
fig = plt.figure()
#plt.xlabel("Iteration number")
#plt.ylabel("Iteration time (s)")

fig, ax = plt.subplots()

x = np.arange(len(itrs_to_plot)) # the label locations
ax.set_xticks(x)
ax.set_xticklabels(itrs_to_plot)

data1 = [23,85, 72, 43, 52]
data2 = [42, 35, 21, 16, 9]

bar_width = 0.3

for engine_idx, engine in enumerate(yvalues_per_engine.keys()):

    y = yvalues_per_engine[engine]
    yerr = stddev_per_engine[engine]


    ax.bar(np.arange(len(y)) + engine_idx * bar_width, y, yerr=yerr, capsize=5, width=bar_width, label=engine)

    #plt.bar(np.arange(len(data2))+ bar_width, data2, width=bar_width)




    #plt.errorbar(x, y , yerr=yerr, label=engine, capsize=3)
    #plt.plot(x, y, label=engine)









plt.legend(loc='upper right')

plt.savefig(args.out_file, dpi=300)

plt.show()

