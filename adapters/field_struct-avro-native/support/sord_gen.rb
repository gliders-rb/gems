# frozen_string_literal: true

# Dev-only stand-in for `sord gen <file> --rbs --no-sord-comments --hide-private --no-regenerate` (SH-B11), run under
# gemfiles/sigs.gemfile. It does what the sord executable does, with one addition: the base gem's signatures
# (field_struct's sig/) are fed to Sord's own resolver (Sord::Resolver.add_rbs_objects_to_paths, a public module
# function), so a YARD type such as +FieldStruct::Field+ resolves without parsing field_struct's source into the YARD
# registry (which would also put the whole base gem into the generated file).
#
#   ruby support/sord_gen.rb <output.rbs> <base gem sig dir>...
require 'pathname'
require 'rbs'
require 'sord'

target, *sig_dirs = ARGV
abort 'usage: sord_gen.rb <output.rbs> <sig dir>...' if target.nil?

YARD::Registry.load!
names = Sord::Resolver.prepare
sig_dirs.each do |dir|
  loader = RBS::EnvironmentLoader.new
  loader.add(path: Pathname(dir))
  env = RBS::Environment.new
  loader.load(env: env)
  Sord::Resolver.add_rbs_objects_to_paths(env, names)
end

options = {
  rbi: false, rbs: true, sord_comments: false, regenerate: false, break_params: 4, replace_errors_with_untyped: false,
  replace_unresolved_with_untyped: false, hide_private: true, exclude_messages: nil, include_messages: nil,
  keep_original_comments: false, skip_constants: false, use_original_initialize_return: false, exclude_untyped: false, tags: []
}
plugin = Sord::ParlourPlugin.new(options)
plugin.parlour = Parlour::RbsGenerator.new(break_params: options[:break_params])
plugin.generate(plugin.parlour.root)
File.write(target, plugin.parlour.rbs)
