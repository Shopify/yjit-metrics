#!/usr/bin/env ruby -w

require "erb"
require "yaml"
require "fileutils"
require "ostruct"

# For now, keep the equivalent of _config.yml in constants
COLLECTIONS = [ "benchmarks" ]
SPECIAL_DIRS = [ "_layouts", "_includes", "_sass", "_framework" ]
TOPLEVEL_SKIPPED = [ "_config.yml" ]

# TODO: handle _sass dir - just pregenerate up-front?

def redcarpet_render_markdown(text)
  require "kramdown"
  Kramdown::Document.new(text).to_html
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

  # This is named for the Jekyll equivalent... The big reason Jekyll
  # needs this is that it may put a site at the root, or at a subdirectory,
  # and so site-'absolute' URLs like the one passed in need to turn into
  # relative URLs that can work when the whole site is in a dir like
  # "/blog" rather than at the root. We're at the root and don't care.
  def relative_url(url)
    raise "URL should not be nil!" if url.nil?

    unless @metadata["url"]
      raise "NO URL IN METADATA: #{url.inspect}"
    end

    url = "/" + url unless url[0] == "/"
    url
  end

  def include(path)
    render_file("_includes/#{path}", @metadata)
  end

  def render_markdown(markdown)
    redcarpet_render_markdown(markdown)
  end
end

def read_front_matter(path)
  contents = File.read(path)

  if contents.start_with?("---\n")
    front_matter, erb_template = contents.delete_prefix("---\n").split("\n---\n", 2)
    front_matter_lines = front_matter.count("\n") + 2 # Two additional lines for the "---" we removed
    return YAML.load(front_matter, symbolize_names: true), front_matter_lines, erb_template
  else
    return {}, 0, contents
  end
end

KNOWN_STEPS = ["erb", "md"]
def render_file_to_location(path, out_dir, metadata)
  FileUtils.mkdir_p(out_dir)
  filename = path.split("/")[-1]

  extensions = path.split(".").reverse[0..-2] # Remove the initial filename
  unless extensions.any? { |ext| KNOWN_STEPS.include?(ext) }
    FileUtils.cp path, "#{out_dir}/#{filename}"
    return
  end

  steps = extensions.take_while { |ext| KNOWN_STEPS.include?(ext) }
  out_filename = out_dir + "/" + filename.delete_suffix("." + steps.reverse.join("."))

  front_matter_data, line_offset, file_content = read_front_matter(path)

  merged_metadata = front_matter_data.merge(metadata)
  merged_metadata[:url] = (out_filename.split("/")[1..-1].select { |p| p != "." }).join("/")
  dsl = RenderContext.new merged_metadata

  # For each step, "content" is the current file content before processing.
  # For a .html.md.erb file, steps will be ["erb", "md"]
  contents = file_content
  steps.each do |step|
    case step
    when "erb"
      erb_tmpl = ERB.new(contents)
      # Multi-step erb pipelines could mess up the line numbers easily
      contents = dsl.instance_eval(erb_tmpl.src, path, 1 + line_offset)
    when "md"
      contents = redcarpet_render_markdown(contents)
    else
      raise "Unknown content-step or file extension: #{step.inspect} out of #{steps.inspect}"
    end
  end

  if merged_metadata[:layout]
    merged_metadata[:content] = contents
    contents = render_file("_layouts/#{merged_metadata[:layout]}.erb", merged_metadata)
  end

  File.write("#{out_filename}", contents)
end

def render_file(path, metadata)
  front_matter_data, line_offset, erb_template = read_front_matter(path)

  #dsl = OpenStruct.new(metadata.merge(front_matter_data).merge(content: ""))
  front_matter_data[:content] = ""  # Overwrite if metadata has :content
  dsl = RenderContext.new metadata.merge(front_matter_data.merge(metadata))
  erb_tmpl = ERB.new(erb_template)
  #erb_tmpl.location = [path, 1 + line_offset]
  text = dsl.instance_eval erb_tmpl.src, path, 1 + line_offset
  #text = erb_tmpl.result(dsl.send(:binding))

  if front_matter_data[:layout]
    return render_file("_layouts/#{front_matter_data[:layout]}.erb", metadata.merge(content: text))
  end

  text
end

def render_collection_item_to_location(item, out_dir, metadata)
  layout = item.layout
  unless layout
    raise "Can't find layout for item #{item["name"].inspect} / #{item.inspect}!"
  end

  # Trim off leading _site for url
  url = "#{out_dir.split("/")[1..-1].join("/")}/#{item[:name]}"
  contents = render_file("_layouts/#{layout}.erb", metadata.merge(page: item, url: url))
  File.write("#{out_dir}/#{item[:name]}", contents)
end

def parse_collections
  out = {}
  COLLECTIONS.each do |coll|
    out[coll] = []
    Dir["_#{coll}/*.md"].each do |file_w_frontmatter|
      item_data, _line, _content = read_front_matter(file_w_frontmatter)
      item_data[:name] = file_w_frontmatter.split("/")[-1].gsub("_", "-") # Ah, Jekyll. There's probably some deep annoying meaning to why this is needed.
      item_data[:url] = "/#{coll}/#{File.basename(file_w_frontmatter.gsub("_", "-"), ".*")}"
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

  coll_data = parse_collections
  site_var = OpenStruct.new coll_data
  metadata = {}
  metadata[:site] = site_var

  # Use a glob pattern that returns immediate children *and* follows one layer of
  # symlinks. See https://stackoverflow.com/questions/357754/can-i-traverse-symlinked-directories-in-ruby-with-a-glob
  Dir["**{,/*/**}/*"].each do |repo_file|
    next if File.directory?(repo_file)

    if repo_file[0] == "_"
      next if repo_file.start_with?("_site/")
      next if TOPLEVEL_SKIPPED.include?(repo_file)
      next if SPECIAL_DIRS.any? { |dir| repo_file.start_with?(dir + "/") }
      next if COLLECTIONS.any? { |coll| repo_file.start_with?("_" + coll) }
      raise "Unexpected repo path starting with underscore: #{repo_file.inspect}"
    end

    out_dir = "_site/#{File.dirname repo_file}"
    render_file_to_location(repo_file, out_dir, metadata)
  end

  # Now build entries for the collections
  COLLECTIONS.each do |collection|
    # Output URL is /:collection_name:/:item_name:
    out_dir = "_site/#{collection}"
    Dir.mkdir out_dir
    coll_data[collection].each do |item|
      render_collection_item_to_location(item, out_dir, metadata)
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
