#!/usr/bin/env python3

import json
import argparse
import numpy as np
import matplotlib.pyplot as plt

# Sample commands:
# ./plot_warmup.py --bench_name=railsbench data/vmil_warmup/*_basic_benchmark_*.json

parser = argparse.ArgumentParser()
parser.add_argument('--bench_name')
parser.add_argument('--out_file', default='railsbench_warmup.png')
parser.add_argument('input_files', nargs='*')
args = parser.parse_args()

# Mapping of Ruby engines to lists of time values
series_per_engine = {}

for filename in args.input_files:
    if 'yjit_stats' in filename:
        continue

    with open(filename) as f:
        data = json.load(f)

    times = data['warmups']
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

# Generate the plot
fig = plt.figure()
plt.xlabel("Total run-time (s)")
plt.ylabel("Iteration time (s)")

plt.xlim(right=750)

for engine, series in series_per_engine.items():
    num_series = len(series)

    y = np.array(series)
    print(y.shape)
    y = y.mean(0)

    total_time = 0
    x = []
    for i in range(len(y)):
        total_time += y[i] / 1000
        x.append(total_time)

    plt.plot(x, y, label=engine)


fig.tight_layout()
plt.legend(loc='upper right')
plt.savefig(args.out_file, dpi=300)
plt.show()
