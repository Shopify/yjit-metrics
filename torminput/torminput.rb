#!/usr/bin/env ruby
# Torminput

require "erb"
require "tempfile"
require "fileutils"
require "optparse"

OPTIONS = {
  ruby: "./miniruby",
  isolate: false,
}
OptionParser.new do |opts|
  opts.banner = "Usage: torminput.rb [options]"

  opts.on("-r RUBY", "Run with a specific Ruby (default: #{OPTIONS[:ruby]})") do |r|
    OPTIONS[:ruby] = r
  end
  opts.on("-i", "--[no-]isolate") do |i|
    OPTIONS[:isolate] = i
  end
end.parse!
if ARGV.length > 0
  raise "Unexpected arguments: #{ARGV.inspect}!"
end

# Run with these Ruby implementations
RUBY_IMPL_ARGS = {
  "CRuby" => "",
  "YJIT" => "--yjit-call-threshold=1",
}

# These are strings, not Ruby objects. No spaces in each item inside %w!
inputs = %w{1 5 3.7 nil true false @undefined :s} +
  %w{"" "".force_encoding("ascii-8bit") "".force_encoding("binary")} +
  %w{"a" "a".force_encoding("ascii-8bit") "a".force_encoding("binary")} +
  %w{[] [1,"a"] {} {a:1} Object.new}

snippet_operations = {
  "simple_plus" => "a + b",
  "simple_shovel" => "a << b",
  "simple_lt" => "a < b",
  "simple_gt" => "a > b",
}

# TODO: add method operations
operations = snippet_operations

##########

# Interesting thing about this method: it accepts strings to
# *print* these objects, not the actual Ruby objects.
def source_for_run(input_obj_strings, receiver_obj_string, first_arg_string, operations_struct)
  # See end of file for Erb template
  @template ||= ERB.new(DATA.read)

  t = {
    inputs: input_obj_strings,
    receiver: receiver_obj_string,
    first_time_arg: first_arg_string,
    operations: operations_struct,
  }
  @template.result(binding)
end

def perform_run(source_path, description)
  impls = RUBY_IMPL_ARGS.keys
  outfiles = impls.map { |name| Tempfile.open("torminput_#{name}_output")}

  impls.each.with_index do |impl_name, idx|
    out_path = outfiles[idx].path
    system("#{OPTIONS[:ruby]} #{RUBY_IMPL_ARGS[impl_name]} #{source_path}>#{out_path}") or raise "Failed running #{impl_name} for #{description}!"
  end

  # If we cut out whitespace, is there any diff?
  # Do pairwise diffs - just one if there's a single Ruby impl, otherwise more.
  key_impl = impls.first
  key_impl_output = outfiles[0].path
  impls.each.with_index do |impl_name, idx|
    next if impl_name == key_impl
    impl_output = outfiles[idx].path
    text_diff = `diff -c #{key_impl_output} #{impl_output}`.strip
    unless text_diff == ""
      puts "Output diffs between #{key_impl} and #{impl} for #{description}:"
      puts text_diff
      print "\n\n==============\n\n"
      raise "Different output! Error!"
    end
  end

ensure
  outfiles.map { |temp| temp.unlink } if outfiles
end

test_runs = []
if OPTIONS[:isolate]
  # By request, use as many runs as possible to be sure exactly what's wrong
  inputs.each do |receiver|
    inputs.each do |first_time_arg|
      operations.each do |op_name, op_text|
        inputs.each do |this_time_arg|
          desc = "Recv: #{receiver.inspect} 1stArg: #{first_time_arg.inspect} Op: #{op_name.inspect} Arg: #{this_time_arg.inspect}"
          test_runs << [[this_time_arg], receiver, first_time_arg, { op_name => op_text }, desc ]
        end
      end
    end
  end
else
  # By default, use as few runs as possible for speed.
  inputs.each do |receiver|
    inputs.each do |first_time_arg|
      desc = "receiver #{receiver.inspect} and first_time_arg #{first_time_arg.inspect}"
      test_runs << [inputs, receiver, first_time_arg, operations, desc]
    end
  end
end

test_runs.each do |inp, recv, first_arg, ops, desc|
  begin
    sourcefile = Tempfile.open("torminput_source")
    sourcefile.write source_for_run(inp, recv, first_arg, ops)
    sourcefile.flush # Don't successfully run empty source files

    perform_run(sourcefile.path, desc)

    # Don't delete this on crash or raise
    sourcefile.unlink if sourcefile
  rescue
    outfile = File.expand_path("./torminput_failure.rb")
    puts "Error running sourcefile... Copied failing file to #{outfile}"
    FileUtils.cp sourcefile.path, outfile if sourcefile
    raise
  end
end

# Below this is the code template for child worker processes
__END__
INPUTS = [ <%= t[:inputs].join(", ") %> ]
recv = <%= t[:receiver] %>
first_time_arg = <%= t[:first_time_arg] %>

# Ensure it's all compiled, avoid early side exits for e.g. cache misses

<% t[:operations].each do |op_name, op_text| %>
def test_<%= op_name %>(a, b)
  <%= op_text %>
rescue
  $! # Exception? Great! Return it.
end
3.times { test_<%= op_name %>(recv, first_time_arg) }
<% end %>

puts("# Output with #{recv.inspect} . #{first_time_arg.inspect}")
<% t[:operations].each do |op_name, op_text| %>
  INPUTS.each do |input|
    # Some operations, like shovel, mutate the receiver.
    # We'll just check receiver, arg and output for all ops.
    recv2 = recv.dup
    arg = input.dup
    output = test_<%= op_name %>(recv, arg)
    puts("<%= op_name %>(#{recv2.inspect}/#{recv.inspect}, #{input.inspect}/#{arg.inspect}) = #{output.inspect}")
  end
<% end %>
