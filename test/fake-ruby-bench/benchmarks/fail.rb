# frozen_string_literal: true

require "harness"

run_benchmark(10) do
  raise "Nope"
end
