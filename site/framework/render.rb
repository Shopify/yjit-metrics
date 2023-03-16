#!/usr/bin/env ruby -w

require "erb"
require "yaml"
require "fileutils"
require "ostruct"

# For now, keep the equivalent of _config.yml in constants
COLLECTIONS = [ "benchmarks" ]
SPECIAL_DIRS = [ "_layouts", "_includes", "_sass" ]
TOPLEVEL_SKIPPED = [ "_config.yml" ]

# TODO: handle _sass dir - just pregenerate up-front?
# TODO: render collections

def redcarpet_render_markdown(text)
  @md_renderer ||= Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true)
  @md_renderer.render(text)
end

# RenderContext is an OpenStruct with some additional helper methods
class RenderContext
  def initialize(metadata)
    @metadata = {}
    metadata.each do |k, v|
      @metadata[k.to_s] = v
    end
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
    render_file("_includes/#{path}", @metadata)
  end

  def render_markdown(markdown)
    redcarpet_render_markdown(markdown)
  end
end

def read_file(path)
  contents = File.read(path)

  if contents.start_with?("---\n")
    front_matter, erb_template = contents.delete_prefix("---\n").split("\n---\n", 2)
    front_matter_lines = front_matter.count("\n") + 2 # Two additional lines for the "---" we removed
    return YAML.load(front_matter, symbolize_names: true), front_matter_lines, erb_template
  else
    return {}, 0, contents
  end
end

def render_file(path, metadata)
  front_matter_data, line_offset, erb_template = read_file(path)

  #dsl = OpenStruct.new(metadata.merge(front_matter_data).merge(content: ""))
  front_matter_data[:content] = ""  # Overwrite if metadata has :content
  dsl = RenderContext.new metadata.merge(front_matter_data.merge(metadata))
  erb_tmpl = ERB.new(erb_template)
  #erb_tmpl.location = [path, 1 + line_offset]
  text = dsl.instance_eval erb_tmpl.src, path, 1 + line_offset
  #text = erb_tmpl.result(dsl.send(:binding))

  if front_matter_data[:layout]
    STDERR.puts "Rendering with layout #{front_matter_data[:layout].inspect} and content #{text[0..10].inspect}"
    return render_file("_layouts/#{front_matter_data[:layout]}.erb", metadata.merge(content: text))
  end

  text
end

def parse_collections
  out = {}
  COLLECTIONS.each do |coll|
    out[coll] = []
    Dir["_#{coll}/*.md"].each do |file_w_frontmatter|
      item_data, _line, _content = read_file(file_w_frontmatter)
      out[coll] << OpenStruct.new(item_data)
    end
  end
  out
end

def build_site
  # cd to root of repo
  Dir.chdir "#{__dir__}/.."

  # Remove old _site directory if present, and replace it with an empty one
  FileUtils.rm_rf "_site"
  Dir.mkdir "_site"

  site_var = OpenStruct.new parse_collections
  metadata = {}
  metadata[:site] = site_var

  Dir["**/*"].each do |repo_file|
    next if File.directory?(repo_file)

    if repo_file[0] == "_"
      next if repo_file.start_with?("_site/")
      next if TOPLEVEL_SKIPPED.include?(repo_file)
      next if SPECIAL_DIRS.any? { |dir| repo_file.start_with?(dir + "/") }
      next if COLLECTIONS.any? { |coll| repo_file.start_with?("_" + coll) }
      raise "Unexpected repo path starting with underscore: #{repo_file.inspect}"
    end

    # Note: detect and render markdown
    # Note: File.extname/File.basename

    if repo_file.end_with?(".erb")
      STDERR.puts "ERB generate: #{repo_file.inspect}"
      out_file = File.join("_site", repo_file).delete_suffix(".erb")
      new_contents = render_file(repo_file, metadata)
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
