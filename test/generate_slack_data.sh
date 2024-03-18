#!/bin/bash

platform () {
  case `uname -m` in
    aarch*|arm*) echo arm;;
    *) echo x86;;
  esac
}

platform="$(platform)"

env YJIT_BENCH_DIR=test/fake-yjit-bench FAKE_YJIT_BENCH_OUTPUT="$PWD/test/data" ./basic_benchmark.rb --skip-git-updates --warmup-itrs=0 --min-bench-time=0.0 --min-bench-itrs=1 --on-errors=report --max-retries=0 --configs="${platform}_yjit_stats,${platform}_prod_ruby_no_jit" --output test/data
