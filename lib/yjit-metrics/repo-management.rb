# For yjit-metrics, we often want to clone various repositories, Ruby and non-Ruby.
# This file is about cloning and managing those repositories, and installing Rubies.

module YJITMetrics; end
module YJITMetrics::RepoManagement
    def clone_repo_with(path:, git_url:, git_branch:, do_clean: true)
        unless File.exist?(path)
            check_call("git clone '#{git_url}' '#{path}'")
        end

        Dir.chdir(path) do
            if do_clean
                check_call("git fetch") # Make sure we can see any new branches - "git checkout" can fail with a not-yet-seen branch
                check_call("git checkout .") # There's a tendency to have local mods to Gemfile.lock -- get rid of those changes
                check_call("git clean -d -f")
                check_call("git checkout #{git_branch}")
                if git_branch =~ /\A[0-9a-zA-Z]{5}/
                    # Don't do a "git pull" on a raw SHA
                else
                    check_call("git pull")
                end
            else
                # If we're not cleaning, we should still make sure we're on the right branch
                current_branch = `git rev-parse --abbrev-ref HEAD`.chomp
                raise("Repo is on incorrect branch #{current_branch.inspect} instead of #{git_branch.inspect}!") if current_branch != git_branch
            end
        end
    end

    def clone_ruby_repo_with(path:, git_url:, git_branch:, config_opts:, config_env: [], install_to:)
        clone_repo_with(path: path, git_url: git_url, git_branch: git_branch)

        Dir.chdir(path) do
            config_opts += [ "--prefix=#{install_to}" ]

            unless File.exist?("./configure")
                check_call("./autogen.sh")
            end

            if !File.exist?("./config.status")
                should_configure = true
            else
                # Right now this config check is brittle - if you give it a config_env containing quotes, for
                # instance, it will tend to believe it needs to reconfigure. We cut out single-quotes
                # because they've caused trouble, but a full fix might need to understand bash quoting.
                config_status_output = check_output("./config.status --conf").gsub("'", "").split(" ").sort
                desired_config = config_opts.sort.map { |s| s.gsub("'", "") } + config_env
                if config_status_output != desired_config
                    puts "Configuration is wrong, reconfiguring..."
                    puts "Desired: #{desired_config.inspect}"
                    puts "Current: #{config_status_output.inspect}"
                    should_configure = true
                end
            end

            if should_configure
                check_call("#{config_env.join(" ")} ./configure #{ config_opts.join(" ") }")
                check_call("make clean")
            end

            check_call("make -j16 install")
        end
    end
end
