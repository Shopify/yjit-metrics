# frozen_string_literal: true

module MetricsApp
  module Benchmarks
    URL = "https://github.com/ruby/ruby-bench.git"
    DIR = MetricsApp::ROOT.join("build", "ruby-bench")

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
