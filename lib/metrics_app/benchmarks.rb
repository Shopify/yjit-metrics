# frozen_string_literal: true

module MetricsApp
  module Benchmarks
    URL = "https://github.com/ruby/ruby-bench.git"
    # Look for it adjacent to this repo's checkout.
    DIR = ENV["YJIT_BENCH_DIR"]&.then { |x| Pathname.new(x) } || MetricsApp::ROOT.parent.join("yjit-bench")

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
      # Rails apps in yjit-bench can leave a bad bootsnap cache - delete them
      Dir.glob("**/*tmp/cache/bootsnap", base: DIR) do |f|
        DIR.join(f).rmtree
      end
    end
  end
end
