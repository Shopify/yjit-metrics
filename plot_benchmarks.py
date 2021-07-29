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
data_per_engine = {}

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

    print(filename)
    print(engine)
    print(times)



    # NOTE: we may have to cut out the warmup iterations




    """
    series = series_per_engine.get(engine, [])

    # Each line should have the same number of iterations
    if len(series) > 0:
        prev_times = series[-1]
    assert len(times) >= 2

    series.append(times)
    series_per_engine[engine] = series
    """



# Array of benchmark names
benchmark_names = []

# Arrays of yvalues and stddev for each engine
# One yvalue per benchmark
yvalues_per_engine = {}
stddev_per_engine = {}





"""
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

    yvalues_per_engine[engine] = mean
    stddev_per_engine[engine] = std
"""










# Generate the plot
fig = plt.figure()
#plt.xlabel("Iteration number")
#plt.ylabel("Iteration time (s)")

fig, ax = plt.subplots()

x = np.arange(len(benchmark_names)) # the label locations
ax.set_xticks(x)
ax.set_xticklabels(benchmark_names)


bar_width = 0.3

for engine_idx, engine in enumerate(yvalues_per_engine.keys()):

    y = yvalues_per_engine[engine]
    yerr = stddev_per_engine[engine]

    ax.bar(np.arange(len(y)) + engine_idx * bar_width, y, yerr=yerr, capsize=5, width=bar_width, label=engine)









plt.legend(loc='upper right')

fig.tight_layout()
plt.savefig(args.out_file, dpi=300)
plt.show()
