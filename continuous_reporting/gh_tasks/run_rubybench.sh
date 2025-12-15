#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If BENCHMARK_RUBY_PATH not set, source install_rubies.sh to set it
if [[ -z "$BENCHMARK_RUBY_PATH" ]]; then
    echo "BENCHMARK_RUBY_PATH not set, running install_rubies.sh..."
    source "$SCRIPT_DIR/install_rubies.sh"
fi

RUBYBENCH_DIR="$HOME/ym/rubybench"
RUBYBENCH_REPO="https://github.com/rubybench/rubybench"
RUBYBENCH_BRANCH="mvh-configure-results-dir"

RUBYBENCH_GIT="git -C $RUBYBENCH_DIR"

if [[ ! -d "$RUBYBENCH_DIR/.git" ]]; then
    git clone --branch "$RUBYBENCH_BRANCH" "$RUBYBENCH_REPO" "$RUBYBENCH_DIR"
fi

pushd "$RUBYBENCH_DIR"

git fetch origin
git checkout "$RUBYBENCH_BRANCH"
git reset --hard "origin/$RUBYBENCH_BRANCH"
git submodule init
git submodule update

echo "Running rubybench with:"
echo "  BENCHMARK_RUBY_PATH=$BENCHMARK_RUBY_PATH"
echo "  BENCHMARK_DATE=$BENCHMARK_DATE"

BENCHMARK_RUBY_PATH="$BENCHMARK_RUBY_PATH" \
BENCHMARK_DATE="$BENCHMARK_DATE" \
./bin/ec2.sh

popd
