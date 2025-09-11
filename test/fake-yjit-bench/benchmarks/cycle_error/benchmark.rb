# frozen_string_literal: true

# Use real ruby-bench harness loader.
real_yjit_bench = File.expand_path('../../../../../yjit-bench', __dir__)
require "#{real_yjit_bench}/harness/loader.rb"

Dir.chdir __dir__
use_gemfile

# Require tempdir so that the tests always start with the same (empty) state.
file = File.join(ENV.fetch('FAKE_YJIT_BENCH_OUTPUT'), '.cycle_error.tmp')

# First attempt should fail, then write the file so that the second attempt can succeed.
should_fail = if File.exist?(file)
                File.unlink(file)
                false
              else
                File.write(file, '')
                true
              end

run_benchmark(10) do
  # Ensure benchmark time is greater than 0.
  sleep 0.25

  if should_fail
    raise RuntimeError, 'Time to fail'
  end

  true
end
