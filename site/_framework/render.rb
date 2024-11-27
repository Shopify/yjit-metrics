#!/usr/bin/env ruby

require "digest"
require "erb"
require "json"
require "yaml"
require "fileutils"
require "ostruct"
require "sass-embedded"
require "shellwords"

REPO_DIR = File.expand_path("../../", __dir__)

def find_dir(path)
  server = File.expand_path("../#{path}", REPO_DIR)
  local = File.expand_path("build/#{path}", REPO_DIR)
  return server if File.exist?(server) && !File.exist?(local)
  local
end

BUILT_YJIT_REPORTS = find_dir("built-yjit-reports")
COLLECTIONS = [ "benchmarks" ]
COLLECTION_BASES = {
  "benchmarks" => BUILT_YJIT_REPORTS,
}
SPECIAL_DIRS = [ "_layouts", "_includes", "_sass", "_framework" ]
TOPLEVEL_SKIPPED = [ "exe", "Gemfile", "Gemfile.lock" ]

def render_markdown(text)
  require "kramdown"
  Kramdown::Document.new(text).to_html
end

def render_scss(content)
  Sass.compile_string(content, load_paths: [File.expand_path("../_sass", __dir__)], style: :compressed).css
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
    return @metadata[name.to_s] if @metadata.key?(name.to_s)

    super
  end

  def respond_to_missing?(name)
    return true if @metadata.key?(name.to_s)

    super
  end

  def page_name
    url.sub(/\.[^.]+$/, '')
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

  RAW_DATA_PREFIX = ENV.fetch('RAW_DATA_PREFIX', 'https://raw.githubusercontent.com/yjit-raw/benchmark-data/refs/heads/main')
  def raw_data_url(path)
    "#{RAW_DATA_PREFIX}/#{path}"
  end

  def include(path)
    raise("Can't include nil or empty string!") if path.nil? || path.empty?

    render_file(File.join(BUILT_YJIT_REPORTS, "_includes", path), @metadata)
  end

  def json(obj)
    JSON.generate(obj)
  end

  PLATFORMS = %w[x86_64 aarch64]
  PLATFORM_PATTERN = Regexp.union(PLATFORMS).to_s
  def find_best(hash, pattern)
    # There are several other keys that would match a more generic pattern so we
    # specifically replace PLATFORM marker with possible values.
    re = Regexp.compile(pattern.gsub(/PLATFORM/, PLATFORM_PATTERN))
    # Get key/value pairs where key matches pattern for platforms.
    pairs = hash.select { |k, v| k.to_s.match?(re) }
    # If present use value with x86 key, else use whatever value we have.
    (pairs.detect { |k,v| k.to_s.match?(/x86_64/) } || pairs.first)[1]
  end

  def render_markdown(markdown)
    render_markdown(markdown)
  end

  TEXT = {
    speed_graph: "Speed of each Ruby implementation relative to the baseline CRuby measurement. Higher is better.",
    memory_graph: "Memory usage of each Ruby implementation relative to the baseline CRuby measurement. Lower is better."
  }

  def text(key)
    TEXT.fetch(key)
  end

  def asset_url(asset)
    path = "assets/#{asset}"
    path += ".scss" if asset.end_with?(".css")
    hash = Digest::MD5.file(File.expand_path(path, File.dirname(__dir__))).hexdigest[0..8]
    "/assets/#{asset}?#{hash}"
  end

  def configure_args(args)
    Shellwords.split(args).map do |arg|
      next if arg.match?(/^--prefix=/)

      # Wrap in single quotes only if it seems necessary.
      arg.match?(%r{^[^-a-zA-Z]|[^[-_a-zA-Z0-9:@\/=]]}) ? "'#{arg}'" : arg
    end.compact
  end

  TIMELINE_EVENTS = YAML.load_file(File.expand_path("../../events.yaml", __dir__))
  def timeline_events
    TIMELINE_EVENTS
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

KNOWN_STEPS = ["erb", "md", "scss"]

# Render the file at path to out_dir, using metadata and the frontmatter in path if present.
# Writes the file to its new location. If path has transformable extensions like .md or .erb,
# the file will be processed using one or multiple steps.
#
# This is the primary top-level method used to render files from source to destination.
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

  puts "## Rendering #{path}"
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
      contents = render_markdown(contents)
    when "scss"
      contents = render_scss(contents)
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

# Render the file at path, using metadata and the frontmatter in path if present.
# Returns the rendered text.
def render_file(path, metadata, no_layout: false)
  raise "Can't render a directory!" if File.directory?(path)

  front_matter_data, line_offset, erb_template = read_front_matter(path)

  #dsl = OpenStruct.new(metadata.merge(front_matter_data).merge(content: ""))
  front_matter_data[:content] = ""  # Overwrite if metadata has :content
  dsl = RenderContext.new metadata.merge(front_matter_data.merge(metadata))
  erb_tmpl = ERB.new(erb_template)
  #erb_tmpl.location = [path, 1 + line_offset]
  text = dsl.instance_eval erb_tmpl.src, path, 1 + line_offset
  #text = erb_tmpl.result(dsl.send(:binding))

  if front_matter_data[:layout] && !no_layout
    return render_file("_layouts/#{front_matter_data[:layout]}.erb", metadata.merge(content: text), no_layout: true)
  end

  text
end

# This is a top-level method used to render a collection item to its location.
def render_collection_item_to_location(item, out_dir, metadata)
  layout = item.layout
  unless layout
    raise "Can't find layout for item #{item["name"].inspect} / #{item.inspect}!"
  end

  # Hack: convert .md to .html
  do_md_conversion = false
  if item[:name].end_with?(".md")
    item[:name].gsub!(/.md$/, ".html")
    item[:name].gsub!(/.html.html$/, ".html") # Don't penalize .html.md, which is more correct
    do_md_conversion = true
  end

  # Trim off leading _site for url
  url = "#{out_dir.split("/")[1..-1].join("/")}/#{item[:name]}"

  contents = item[:content]
  contents = render_markdown(contents) if do_md_conversion
  contents = render_file("_layouts/#{layout}.erb", metadata.merge(page: item, url: url, contents: contents), no_layout: true)

  File.write("#{out_dir}/#{item[:name]}", contents)
end

def parse_collections
  out = {}
  COLLECTIONS.each do |coll|
    out[coll] = []
    glob_with_base("_#{coll}/*.md", COLLECTION_BASES[coll]).each do |file_w_frontmatter, base|
      item_data, _line, content = read_front_matter(File.join(base, file_w_frontmatter))
      item_data[:name] = file_w_frontmatter.split("/")[-1].gsub("_", "-") # Ah, Jekyll. There's probably some deep annoying meaning to why this is needed.
      item_data[:url] = "/#{coll}/#{File.basename(file_w_frontmatter.gsub("_", "-"), ".*")}"
      item_data[:url] += '.html' unless item_data[:url].end_with?('.html')
      item_data[:content] = content
      out[coll] << OpenStruct.new(item_data)
    end
  end
  out
end

def glob_with_base(glob, base)
  Dir[glob, base: base].map { |f| [f, base] }
end

def find_files
  glob_with_base('**/*', File.expand_path('..', __dir__)) +
  glob_with_base('reports/**/*', BUILT_YJIT_REPORTS)
end

def build_site
  # cd to root of builder dir
  Dir.chdir "#{__dir__}/.."

  # Remove old _site directory if present, and replace it with an empty one
  FileUtils.rm_rf "_site"
  Dir.mkdir "_site"

  if File.exist?("autocopy.yml")
    require "yaml"
    autocopy = YAML.load(File.read("autocopy.yml"))
    autocopy.each do |src, dest|
      dest = File.expand_path(dest, BUILT_YJIT_REPORTS)
      FileUtils.mkdir_p dest

      src_files = glob_with_base(src, BUILT_YJIT_REPORTS).map { |f, b| File.join(b, f) }
      next if src_files.empty?

      FileUtils.ln src_files, dest, force: true
    end
  end

  coll_data = parse_collections
  site_var = OpenStruct.new coll_data
  metadata = {}
  metadata[:site] = site_var

  find_files.each do |repo_file, base|
    full_path = File.join(base, repo_file)
    next if File.directory?(full_path)
    next if TOPLEVEL_SKIPPED.include?(repo_file)

    if repo_file[0] == "_"
      next if repo_file.start_with?("_site/")
      next if SPECIAL_DIRS.any? { |dir| repo_file.start_with?(dir + "/") }
      next if COLLECTIONS.any? { |coll| repo_file.start_with?("_" + coll) }

      raise "Unexpected repo path starting with underscore: #{repo_file.inspect}"
    end

    out_dir = "_site/#{File.dirname repo_file}"
    render_file_to_location(full_path, out_dir, metadata)
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

# Jekyll has various subcommands. Build and server are the two I care about.

no_build = ARGV.delete("--no-build")

if ARGV == ["server"] || ARGV == ["serve"]
  puts "Building site..."
  build_site unless no_build

  require "webrick"
  doc_dir = File.join(__dir__, "../_site")
  puts "Starting server at http://localhost:8000, serving #{doc_dir}..."
  servers = [
    WEBrick::HTTPServer.new(:Port => 8000, :DocumentRoot => doc_dir),
    WEBrick::HTTPServer.new(:Port => 8001, :DocumentRoot => find_dir('raw-benchmark-data')),
  ]
  trap('INT') {
    servers.map(&:shutdown)
  }
  servers.map { |s| Thread.new { s.start } }.map(&:join)
elsif ARGV == ["build"]
  build_site
else
  raise "Real arg parsing would be good. Args: #{ARGV.inspect}"
end
