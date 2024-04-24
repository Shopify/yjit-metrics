#!/bin/bash -l

set -e

cd ~/ym/raw-yjit-reports

git fetch
git checkout .
git pull
