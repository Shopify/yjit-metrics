# frozen_string_literal: true

module MetricsApp
  module RepoManagement
    def clone_repo(url, path, branch: nil)
      unless File.exist?(path)
        # Git clone will make any necessary parent dirs.
        check_call("git", "clone", url, path)
        return unless branch
      end

      chdir(path) do
        check_call("git clean -d -f -x")
        check_call("git checkout . 2>&1") # There's a tendency to have local mods to Gemfile.lock -- get rid of those changes
        check_call("git fetch") # Make sure we can see any new branches - "git checkout" can fail with a not-yet-seen branch

        if branch
          check_call("git checkout #{branch.dump} 2>&1")
          # Only pull if we are on a branch.
          if system("git symbolic-ref HEAD 2>&-")
            check_call("git pull")
          end
        end
      end
    end
  end
end
