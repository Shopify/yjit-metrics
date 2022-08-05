#!/usr/bin/env ruby
# Torminput

require "erb"
require "tempfile"
require "fileutils"



RUBY = "./miniruby"

# These are strings, not Ruby objects. No spaces in each item inside %w!
inputs = %w{1 5 3.7 nil true false :s} +
  %w{"" "".force_encoding("ascii-8bit") "".force_encoding("binary")} +
  %w{"a" "a".force_encoding("ascii-8bit") "a".force_encoding("binary")} +
  %w{[] [1,"a"] {} {a:1}}

snippet_operations = {
  "simple_plus" => "a + b",
  "simple_shovel" => "a << b",
  "simple_lt" => "a < b",
  "simple_gt" => "a > b",
}

# TODO: add method operations
operations = snippet_operations

# See end of file for Erb template
template = ERB.new(DATA.read)

inputs.each do |receiver|
  inputs.each do |first_time_arg|
    begin
      sourcefile = Tempfile.open("torminput_source")
      sourcefile.write template.result(binding) # Capture locals for Erb template
      sourcefile.flush # Don't successfully run empty source files

      cruby_outfile = Tempfile.open("torminput_cruby_out")
      yjit_outfile = Tempfile.open("torminput_yjit_out")
      system("#{RUBY} #{sourcefile.path}>#{cruby_outfile.path}") || raise("Failed running CRuby source for #{receiver} / #{first_time_arg}!")
      system("#{RUBY} --yjit-call-threshold=1 #{sourcefile.path}>#{yjit_outfile.path}") || raise("Failed running YJIT source for #{receiver} / #{first_time_arg}!")

      # If we cut out whitespace, is there any diff?
      text_diff = `diff -c #{cruby_outfile.path} #{yjit_outfile.path}`.strip
      unless text_diff == ""
        puts "For receiver #{receiver} and arg #{first_time_arg}, there were output diffs between CRuby and YJIT:"
        puts text_diff
        print "\n\n==============\n\n"
        raise "Different output! Error!"
      end

      # Don't delete these on crash or raise
      sourcefile.unlink if sourcefile
      cruby_outfile.unlink if cruby_outfile
      yjit_outfile.unlink if yjit_outfile
    rescue
      outfile = File.expand_path("./torminput_failure.rb")
      puts "Error running sourcefile... Copied failing file to #{outfile}"
      FileUtils.cp sourcefile.path, outfile if sourcefile
      raise
    end
  end
end


# Below this is the code template for child worker processes
__END__
INPUTS = [ <%= inputs.join(", ") %> ]
recv = <%= receiver %>
first_time_arg = <%= first_time_arg %>

# Ensure it's all compiled, avoid early side exits for e.g. cache misses

<% operations.each do |op_name, op_text| %>
def test_<%= op_name %>(a, b)
  <%= op_text %>
rescue
  $! # Exception? Great! Return it.
end
3.times { test_<%= op_name %>(recv, first_time_arg) }
<% end %>

puts("# Output with #{recv.inspect} . #{first_time_arg.inspect}")
<% operations.each do |op_name, op_text| %>
  INPUTS.each do |input|
    # Some operations, like shovel, mutate the receiver.
    # We'll just check receiver, arg and output for all ops.
    recv2 = recv.dup
    arg = input.dup
    output = test_<%= op_name %>(recv, arg)
    puts("<%= op_name %>(#{recv2.inspect}/#{recv.inspect}, #{input.inspect}/#{arg.inspect}) = #{output.inspect}")
  end
<% end %>
