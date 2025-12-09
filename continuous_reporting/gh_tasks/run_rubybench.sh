#!/bin/bash
set -e

RUBYBENCH_DIR="$HOME/ym/rubybench"
RUBYBENCH_REPO="https://github.com/rubybench/rubybench"
RUBYBENCH_BRANCH="mvh-configure-results-dir"

RUBYBENCH_GIT="git -C $RUBYBENCH_DIR"

if [[ ! -d "$RUBYBENCH_DIR/.git" ]]; then
    git --branch "$RUBYBENCH_BRANCH" "$REPO" "$RUBYBENCH_DIR"
fi

pushd "$RUBYBENCH_DIR"

git fetch origin
git checkout "$RUBYBENCH_BRANCH"
git reset --hard "origin/$RUBYBENCH_BRANCH"
git submodule init
git submodule update

./bin/ec2.sh

popd
