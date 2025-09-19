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

  CommandExitedNonZero = Class.new(RuntimeError) do
    attr_reader :stderr
    def initialize(command, pwd, err)
      @stderr = err
      super("Command #{command.inspect} failed in directory #{pwd}")
    end
  end

  def check_call(*command, env: {}, **kw)
    # Use prefix to makes it easier to see in the log.
    puts("\e[33m## [#{Time.now}] #{command}\e[00m")

    status = nil
    err_capture = +""
    Benchmark.realtime do
      stderr_r, stderr_w = IO.pipe

      opts = {
        err: stderr_w,
      }.merge(kw)

      pid = Process.spawn(env, *command, opts)
      wait_thread = Process.detach(pid)
      stderr_w.close

      read_loop(stderr_r) do |text|
        # Stream to parent process
        STDERR.write(text)
        # Capture for error notifications
        err_capture << text
      end

      stderr_r.close
      status = wait_thread.value
    end.tap do |time|
      printf "\e[34m## (`%s` took %.2fs)\e[00m\n", command, time
    end

    unless status.success?
      raise CommandExitedNonZero.new(command, Dir.pwd, err_capture)
    end

    status
  end

  def read_loop(io)
    loop do
      begin
        yield(io.readpartial(4096))
      rescue EOFError
        break
      end
    end
  end

  def load_yaml_file(file)
    YAML.load_file(file, aliases: true, symbolize_names: true)
  end
end
