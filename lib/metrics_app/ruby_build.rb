# frozen_string_literal: true

module MetricsApp
  module RubyBuild
    GIT_URL = "https://github.com/rbenv/ruby-build.git"
    DIR = MetricsApp::ROOT.join("build/ruby-build")

    extend self

    def exe_path
      DIR.join("bin", "ruby-build")
    end

    def prepare!
      MetricsApp.clone_repo GIT_URL, DIR
    end

    def run(*args)
      prepare! unless File.exist?(exe_path)

      Dir.chdir(DIR) do
        MetricsApp.check_call(
          exe_path,
          *args,
          env: {"RUBY_CONFIGURE_OPTS" => "--disable-shared"}
        )
      end
    end

    alias install run
  end
end
