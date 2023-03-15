#!/usr/bin/env ruby -w

require "erb"
require "yaml"
require "fileutils"

# For now, keep the equivalent of _config.yml in constants
COLLECTIONS = [ "benchmarks" ]
SPECIAL_DIRS = [ "_layouts", "_includes", "_sass" ]
TOPLEVEL_SKIPPED = [ "_config.yml" ]

# TODO: handle _sass dir - just pregenerate?
# TODO: load collections
# TODO: render collections

def all_collections
  COLLECTIONS.each do |collection_name|
    Dir["_#{collection_name}/*.yml"].each do |item|
    end
  end
end

class RenderContext
  def initialize(metadata)
    @metadata = metadata
  end

  # Used for layouts
  def content
    @metadata["content"]
  end

  def method_missing(name, *args, **keywords)
    if @metadata[name.to_s]
      return @metadata[name.to_s]
    end
    super
  end

  def respond_to_missing?(name)
    return true if @metadata[name.to_s]
    super
  end

  def relative_url(url)
    url # This is gonna be wrong
  end

  def include(path)
    render_file(path, @metadata)
  end
end

def read_file(path)
  contents = File.read(path)

  if contents.start_with?("---\n")
    front_matter, erb_template = contents.delete_prefix("---\n").split("\n---\n", 2)
    front_matter_lines = front_matter.count("\n") + 2 # Two additional lines for the "---" we removed
    STDERR.puts "Front_matter_lines: #{front_matter_lines.inspect} front_matter: #{front_matter.inspect}"
    return YAML.load(front_matter), front_matter_lines, erb_template
  else
    return {}, 0, contents
  end
end

def render_file(path, metadata)
  front_matter_data, line_offset, erb_template = read_file(path)

  dsl = RenderContext.new(metadata.merge(front_matter_data).merge("content" => ""))
  erb_tmpl = ERB.new(erb_template)
  erb_tmpl.location = [path, 1 + line_offset]
  text = erb_tmpl.result(dsl.send(:binding))

  if front_matter_data[:layout]
    return render_file("_layouts/#{front_matter[:layout]}.erb", metadata.merge("content" => text))
  end

  text
end

def build_site
  # cd to root of repo
  Dir.chdir "#{__dir__}/.."

  # Remove old _site directory if present, and replace it with an empty one
  FileUtils.rm_rf "_site"
  Dir.mkdir "_site"

  Dir["**/*"].each do |repo_file|
    next if File.directory?(repo_file)

    if repo_file[0] == "_"
      next if repo_file.start_with?("_site/")
      next if TOPLEVEL_SKIPPED.include?(repo_file)
      next if SPECIAL_DIRS.any? { |dir| repo_file.start_with?(dir + "/") }
      next if COLLECTIONS.any? { |coll| repo_file.start_with?("_" + coll) }
      raise "Unexpected repo path starting with underscore: #{repo_file.inspect}"
    end

    # Note: File.extname/File.basename

    if repo_file.end_with?(".erb")
      STDERR.puts "ERB generate: #{repo_file.inspect}"
      out_file = File.join("_site", repo_file).delete_suffix(".erb")
      new_contents = render_file(repo_file, {})
      File.write(out_file, new_contents)
    else
      out_loc = "_site/#{repo_file}"
      FileUtils.mkdir_p(File.dirname(out_loc))
      FileUtils.cp(repo_file, out_loc)
    end
  end
end

# Jekyll has a few subcommands. Build and server are the two I care about.
if ARGV == ["server"]
  raise "Add server code here"
elsif ARGV == ["build"]
  build_site
else
  raise "Real arg parsing would be good. Args: #{ARGV.inspect}"
end
