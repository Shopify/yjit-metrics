# frozen_string_literal: true

module MetricsApp
  module Benchmarks
    URL = "https://github.com/ruby/ruby-bench.git"
    # Env var is used by tests.
    DIR = ENV["RUBY_BENCH_DIR"]&.then { |x| Pathname.new(x) } || MetricsApp::ROOT.join("build", "ruby-bench")

    extend self

    def prepare!(url, branch:)
      MetricsApp.clone_repo(
        url || URL,
        DIR.to_s,
        branch: branch || "main",
      )
      clean!
    end

    def clean!
      # Rails apps in ruby-bench can leave a bad bootsnap cache - delete them
      Dir.glob("**/*tmp/cache/bootsnap", base: DIR) do |f|
        DIR.join(f).rmtree
      end
    end
  end
end
