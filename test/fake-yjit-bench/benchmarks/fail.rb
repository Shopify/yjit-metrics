# frozen_string_literal: true

# Use real yjit-bench harness loader.
real_yjit_bench = File.expand_path('../../../../yjit-bench', __dir__)
require "#{real_yjit_bench}/harness/loader.rb"

run_benchmark(10) do
  raise "Nope"
end
