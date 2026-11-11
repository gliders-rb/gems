# frozen_string_literal: true

require 'rubocop'
require_relative '../actionable'
require_relative 'verb_position/class_scan'
require_relative 'rubocop/cop/verb_not_last'

begin
  require 'lint_roller'
  require_relative 'rubocop/plugin'
rescue LoadError
  # Older RuboCop (before the plugin API): `require: actionable/rubocop` injects the shipped config instead.
  path = File.join(__dir__, 'rubocop', 'config.yml')
  hash = RuboCop::ConfigLoader.send(:load_yaml_configuration, path)
  config = RuboCop::Config.new(hash, path).tap(&:make_excludes_absolute)
  config = RuboCop::ConfigLoader.merge_with_default(config, path)
  RuboCop::ConfigLoader.instance_variable_set(:@default_configuration, config)
end
