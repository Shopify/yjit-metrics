# frozen_string_literal: true

module MetricsApp
  module RepoManagement
    def clone_repo(url, path, branch: nil)
      unless File.exist?(path)
        check_call("git", "clone", url, path)
        return unless branch
      end

      chdir(path) do
        check_call("git clean -d -f")
        check_call("git checkout .") # There's a tendency to have local mods to Gemfile.lock -- get rid of those changes
        check_call("git fetch") # Make sure we can see any new branches - "git checkout" can fail with a not-yet-seen branch

        if branch
          check_call("git", "checkout", branch)
          # Only pull if we are on a branch.
          if system("git symbolic-ref HEAD 2>&-")
            check_call("git pull")
          end
        end
      end
    end

    def clone_ruby_repo(url, path, branch:, configure_args:, env: nil, prefix:)
      clone_repo(url, path, branch: branch)

      # We are running under bundler so don't let our setup confuse anything in
      # the ruby build commands.
      env = {
        'RUBYLIB' => nil,
        'RUBYOPT' => nil,
        'BUNDLER_SETUP' => nil,
        'BUNDLE_GEMFILE' => nil,
      }.merge(env || {})

      chdir(path) do
        unless File.exist?("./configure")
          check_call("./autogen.sh", env:)
        end

        check_call(
          "./configure",
          "--prefix=#{prefix}",
          "--disable-install-doc",
          "--disable-install-rdoc",
          *configure_args,
          env:,
        )

        check_call("make -j16", env:)
        check_call("make install", env:)
      end
    end
  end
end
