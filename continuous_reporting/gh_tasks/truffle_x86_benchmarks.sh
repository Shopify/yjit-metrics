#!/bin/bash -l
# Note: may need a login shell, depending how chruby is installed.

set -e

cd ~/
rm -rf truffleruby-head
curl -L https://github.com/ruby/truffleruby-dev-builder/releases/latest/download/truffleruby-head-ubuntu-20.04.tar.gz | tar xz
export PATH="$PWD/truffleruby-head/bin:$PATH"
$PWD/truffleruby-head/lib/truffle/post_install_hook.sh
unset GEM_HOME GEM_PATH
ruby -v # Should be Truffle

cd ~/ym/yjit-bench
git checkout main
git checkout .
git pull
MAX_TIME=600 ./run_benchmarks.rb --harness=harness-warmup --out_path=/home/ubuntu/truffle-data/

echo "Completed TruffleRuby benchmarking successfully."
