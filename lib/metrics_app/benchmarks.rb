# frozen_string_literal: true

module MetricsApp
  module Benchmarks
    URL = "https://github.com/ruby/ruby-bench.git"
    # Look for it adjacent to this repo's checkout.
    DIR = ENV["RUBY_BENCH_DIR"]&.then { |x| Pathname.new(x) } || MetricsApp::ROOT.parent.join("ruby-bench")

    extend self

    def prepare!(url, branch:)
      MetricsApp.clone_repo(
        url || URL,
        DIR,
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
