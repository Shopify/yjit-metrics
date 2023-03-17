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
# Note: as of 2023-03-17, chunky_png doesn't work with latest Truffle nightly
./run_benchmarks.rb --harness=harness-warmup --out_path=/home/ubuntu/truffle-data/ 30_ifelse 30k_methods activerecord binarytrees cfunc_itself erubi erubi_rails etanni fannkuchredux fib getivar hexapdf keyword_args lee liquid-c liquid-render mail nbody optcarrot psych-load railsbench respond_to ruby-json ruby-lsp rubykon sequel setivar setivar_object str_concat throw

echo "Completed TruffleRuby benchmarking successfully."
