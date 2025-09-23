# frozen_string_literal: true

require "json"

require_relative "test_helper"

class TimeoutTest < Minitest::Test
  def test_no_timeout
    result = run_script <<~EOF
      echo ok
    EOF
    refute(result[:failed])
    assert_operator(result[:duration], :<, 5)
    assert_equal(result[:exit_status], 0)
    assert_equal("ok\n", result[:output])
    [
      result[:stderr],
      result[:main_stderr],
    ].each do |stderr|
      refute_match(/Timeout/, stderr)
    end
  end

  def test_timeout_term
    result = run_script <<~EOF
      echo sleeping
      cleanup () {
        echo signaled >&2
        sleep 2
        exit 1
      }
      trap cleanup TERM
      for i in `seq 10`; do
        echo $i
        sleep 2
      done
    EOF
    assert(result[:failed])
    assert_operator(result[:duration], :>, 5)
    out = result[:output]
    assert_match(/sleeping/, out)
    assert_match(/1/, out)
    assert_match(/signaled/, result[:stderr])
    [
      result[:stderr],
      result[:main_stderr],
    ].each do |stderr|
      assert_match(/Timeout reached, killing/, stderr)
      refute_match(/Process still alive, killing/, stderr)
    end
  end

  def test_timeout_kill
    result = run_script <<~EOF
      echo sleeping
      signaled=false
      cleanup () {
        echo signaled >&2
        signaled=true
      }
      trap cleanup TERM
      for i in `seq 10`; do
        echo $i s:$signaled
        sleep 2
      done
    EOF
    assert(result[:failed])
    assert_operator(result[:duration], :>, 10)
    out = result[:output]
    assert_match(/sleeping/, out)
    assert_match(/\d+ s:false/, out)
    assert_match(/\d+ s:true/, out)
    assert_match(/signaled/, result[:stderr])
    [
      result[:stderr],
      result[:main_stderr],
    ].each do |stderr|
      assert_match(/Timeout reached, killing/, stderr)
      assert_match(/Process still alive, killing/, stderr)
    end
  end

  def run_script(script)
    stderr_r, stderr_w = IO.pipe
    # Fork to capture all stdout in addition to the method result.
    IO.popen('-', 'r') do |pipe|
      if pipe
        # parent
        out, result = pipe.read.split(/\n---\n/)
        # This is the return value.
        JSON.parse(result, symbolize_names: true).tap do |result|
          result[:main_stdout] = out
          stderr_w.close
          result[:main_stderr] = stderr_r.read
        end
      else
        # child
        STDERR.reopen(stderr_w)
        # All stdout goes to the pipe.
        result = YJITMetrics.run_harness_script_from_string(
          script,
          do_echo: false,
          timeout: 5,
          term_timeout: 5
        )
        # After all output we serialize the return value.
        puts "\n---"
        puts JSON.generate(result)
      end
    end
  end
end
