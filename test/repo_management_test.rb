# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"
require "fileutils"

class RepoManagementTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("repo_management_test")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_clone_repo_skips_git_operations_for_non_git_directory
    non_git_dir = File.join(@temp_dir, "non-git-dir")
    FileUtils.mkdir_p(non_git_dir)
    File.write(File.join(non_git_dir, "test.txt"), "content")

    commands_run = []
    test_module = Module.new do
      extend MetricsApp::RepoManagement

      define_singleton_method(:check_call) do |*args|
        commands_run << args
      end

      define_singleton_method(:chdir) do |path, &block|
        Dir.chdir(path, &block)
      end
    end

    test_module.clone_repo("https://example.com/repo.git", non_git_dir, branch: "main")

    assert_empty commands_run, "Expected no git commands to run for non-git directory"
  end

  def test_clone_repo_clones_when_directory_does_not_exist
    new_dir = File.join(@temp_dir, "new-repo")
    commands_run = []
    test_module = Module.new do
      extend MetricsApp::RepoManagement

      define_singleton_method(:check_call) do |*args|
        commands_run << args
        FileUtils.mkdir_p(new_dir) if args.include?("clone")
      end

      define_singleton_method(:chdir) do |path, &block|
        Dir.chdir(path, &block)
      end
    end

    test_module.clone_repo("https://example.com/repo.git", new_dir)

    assert_equal 1, commands_run.size
    assert_equal ["git", "clone", "https://example.com/repo.git", new_dir], commands_run.first
  end
end
