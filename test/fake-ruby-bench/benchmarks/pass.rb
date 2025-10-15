# frozen_string_literal: true

# Use real ruby-bench harness loader.
real_yjit_bench = File.expand_path('../../../build/ruby-bench', __dir__)
require "#{real_yjit_bench}/harness/loader.rb"

i = 0
run_benchmark(10) do
  i = i + 1
  handle = (i % 2 == 0 ? :STDOUT : :STDERR)
  Object.const_get(handle).puts sprintf("using %s", handle.to_s)
  sleep 0.25
end
