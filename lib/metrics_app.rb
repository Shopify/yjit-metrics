# frozen_string_literal: true

require "benchmark"
require "pathname"
require "yaml"

module MetricsApp
  ROOT = Pathname.new(__dir__).parent

  autoload :Benchmarks,          "#{__dir__}/metrics_app/benchmarks"
  autoload :RepoManagement,      "#{__dir__}/metrics_app/repo_management"
  autoload :Rubies,              "#{__dir__}/metrics_app/rubies"
  autoload :RubyBuild,           "#{__dir__}/metrics_app/ruby_build"

  extend self

  include RepoManagement

  PLATFORMS = %w[ x86_64 aarch64 ]
  PLATFORM = `uname -m`.chomp.downcase.sub(/^arm(\d+)$/, 'aarch\1').then do |uname|
    PLATFORMS.detect { |platform| uname == platform }
  end
  raise("This app only supports these platforms: #{PLATFORMS.join(", ")}") if !PLATFORM

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

  def load_yaml_file(file)
    YAML.load_file(file, aliases: true, symbolize_names: true)
  end
end
