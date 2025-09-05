# frozen_string_literal: true

require "benchmark"
require "pathname"

module MetricsApp
  ROOT = Pathname.new(__dir__).parent

  autoload :RepoManagement,      "#{__dir__}/metrics_app/repo_management"
  autoload :RubyBuild,           "#{__dir__}/metrics_app/ruby_build"

  extend self

  include RepoManagement

  def chdir(dir, &block)
    puts "### cd #{dir}"
    Dir.chdir(dir, &block).tap do
      puts "### cd #{Dir.pwd}" if block
    end
  end

  def check_call(*command, env: {})
    # Use prefix to makes it easier to see in the log.
    puts("\e[33m## [#{Time.now}] #{command}\e[00m")

    status = nil
    Benchmark.realtime do
      status = system(env, *command)
    end.tap do |time|
      printf "\e[34m## (`%s` took %.2fs)\e[00m\n", command, time
    end

    unless status
      raise "Command #{command.inspect} failed in directory #{Dir.pwd}"
    end
  end
end
