#!/usr/bin/env python3

import json
import argparse
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.ticker import StrMethodFormatter

# Sample commands:
# ./plot_warmup_bars.py --bench_name=psych-load data/partial_warmup_data/2021-07-21-*_basic_benchmark_*prod*
# ./plot_warmup_bars.py --bench_name=activerecord data/aws_long_run_warmups/*_basic_benchmark_*.json

parser = argparse.ArgumentParser()
#parser.add_argument('--bench_name')
parser.add_argument('--out_file', default='production.png')
#parser.add_argument('input_files', nargs='*')
args = parser.parse_args()


data = {
    "CRuby 3.0.2 (prod)":
    {
    "count":"339795929",
    "average":"162.2979098610684",
    "median":"34",
    "p75":"161.47477793008676",
    "p95":"643.5682583738514",
    "p99":"1932.0411047973118",
    "stdev":"373.1192465274919"
    },

    "YJIT (canaries)":
    {
    "count":"15705321",
    "average":"121.49548455583938",
    "median":"32",
    "p75":"139.99865417311443",
    "p95":"473.1830629165932",
    "p99":"1027.4873041434569",
    "stdev":"255.21429113827307"
    },
}



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
ax.yaxis.set_major_formatter(StrMethodFormatter('{x:,.0f}'))

# Set the label locations and names
ax.set_xticks([1, 2, 3, 4])
ax.set_xticklabels(["mean", "p75", "p95", "p99"])
ax.set_ylabel("Time (ms)")

bar_width = 0.3

for engine_idx, engine in enumerate(data.keys()):
    print(engine)

    # For each engine, I want 4 points, mean, p75, p95, p99
    # Presumably, we want the mean columns to be grouped together

    values = data[engine]
    values = [float(values["average"]), float(values["p75"]), float(values["p95"]), float(values["p99"])]
    print(values)

    xcoords = np.array([1, 2, 3, 4]) + engine_idx * bar_width

    ax.bar(xcoords, values, width=bar_width, label=engine)








plt.legend(loc='upper left')
fig.tight_layout()

plt.savefig(args.out_file, dpi=300)

plt.show()

