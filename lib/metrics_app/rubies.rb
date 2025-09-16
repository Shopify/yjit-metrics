# frozen_string_literal: true

require "shellwords"

module MetricsApp
  module Rubies
    BUILD_DIR = MetricsApp::ROOT.join("build", "ruby-clones")
    INSTALL_DIR = Pathname.new(ENV["RUBIES_DIR"] || "#{ENV["HOME"]}/.rubies")

    extend self

    def build_config(name)
      config[:builds][name.to_sym]
    end

    def build_names(config_names)
      config_names.map { |n| platform_config(n)[:build] }.uniq
    end

    def clean_all!(config_names)
      build_names(config_names).each do |build_name|
        rmtree(INSTALL_DIR.join(build_name))
      end
    end

    def config
      @config ||= MetricsApp.load_yaml_file(MetricsApp::ROOT.join("rubies.yaml")).then do |config|
        config.update(
          platform_configs: config[:runtime_configs].flat_map do |k, v|
            MetricsApp::PLATFORMS.map do |platform|
              ["#{platform}_#{k}".to_sym, v]
            end
          end.to_h
        )
      end
    end

    def install_all!(config_names, rebuild: true, overrides: nil)
      clean_all!(config_names) if rebuild

      BUILD_DIR.mkpath
      build_names(config_names).each do |build_name|
        build = config[:builds][build_name.to_sym]
        prefix = INSTALL_DIR.join(build_name)

        if File.exist?(prefix) && !rebuild
          puts "Skipping #{build_name.dump}: already exists and rebuild is false"
          next
        end

        case build[:install]
        when "ruby-build"
          puts "Installing Ruby #{build_name} via ruby-build"
          MetricsApp::RubyBuild.install(build_name.sub(/^ruby-/, ''), prefix)
        when "repo"
          build_config = build.merge((overrides&.dig(build[:override_name].to_sym) || {}))
          url = build[:git_url]
          branch = build[:git_branch]
          puts "Installing Ruby #{build_name} from #{url}##{branch}"

          # The ruby clone path cannot contain certain characters
          # lest make try to interpolate something and break.
          dir = File.join(BUILD_DIR, url.gsub(%r{[.:/]}) { |c| sprintf ".%02d", c.ord })

          install_from_repo(
            url,
            dir,
            branch:,
            prefix:,
            configure_args: build[:configure_args],
            env: build[:env],
          )
        else
          raise "Unrecognized installation method: #{build[:install].inspect}!"
        end
      end

      true
    end

    def install_from_repo(url, path, branch:, configure_args:, env: nil, prefix:)
      # This will clone, clean, and checkout.
      MetricsApp.clone_repo(url, path, branch: branch)

      # We are running under bundler so don't let our setup confuse anything in
      # the ruby build commands.
      env = {
        'RUBYLIB' => nil,
        'RUBYOPT' => nil,
        'BUNDLER_SETUP' => nil,
        'BUNDLE_GEMFILE' => nil,
      }.merge(env || {})

      MetricsApp.chdir(path) do
        unless File.exist?("./configure")
          MetricsApp.check_call("./autogen.sh", env:)
        end

        extra_config_options = []
        if ENV["RUBY_CONFIG_OPTS"]
          extra_config_options = Shellwords.split(ENV["RUBY_CONFIG_OPTS"])
        elsif RUBY_PLATFORM["darwin"] && !`which brew`.empty?
          %w[
            openssl@3
            openssl@1.1
          ].each do |pkg|
            ossl_prefix = `brew --prefix #{pkg.dump}`.chomp
            if !ossl_prefix.empty?
              extra_config_options = [ "--with-openssl-dir=#{ossl_prefix}" ]
              break
            end
          end
        end

        MetricsApp.check_call(
          "./configure",
          "--prefix=#{prefix}",
          "--disable-install-doc",
          "--disable-install-rdoc",
          *configure_args,
          *extra_config_options,
          env:,
        )

        MetricsApp.check_call("make -j16", env:)
        MetricsApp.check_call("make install", env:)
      end
    end

    def path(config_name)
      INSTALL_DIR.join(platform_config(config_name)[:build])
    end

    def platform_config(name)
      config[:platform_configs][name.to_sym]
    end

    def rmtree(path)
      puts "Removing #{path}"
      path.rmtree
    end

    def ruby(config_name)
      path(config_name).join("bin", "ruby")
    end
  end
end
