#!/bin/bash

platform () {
  case `uname -m` in
    aarch*|arm*) echo arm;;
    *) echo x86;;
  esac
}

platform="$(platform)"

dir="$(mktemp -d -t slack-data)"

export YJIT_BENCH_DIR=test/fake-yjit-bench FAKE_YJIT_BENCH_OUTPUT="$dir"
./basic_benchmark.rb --skip-git-updates \
  --warmup-itrs=0 --min-bench-time=0.0 --min-bench-itrs=1 \
  --on-errors=report --max-retries=1 \
  --configs="${platform}_yjit_stats,${platform}_prod_ruby_no_jit" \
  --output "$dir"

dest="test/data/slack"
rm -rf "$dest"
mkdir -p "$dest"

for i in "$dir"/*.json; do
  base="${i##*/}"
  mv "$i" "test/data/slack/${base#*_}"
done

rm -rf "$dir"
