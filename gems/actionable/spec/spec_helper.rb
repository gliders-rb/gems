# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start { enable_coverage :branch }
end

# The ActiveSupport lane (rake spec:active_support, SH-B22): ActiveSupport loads before the gem and its
# deprecations raise, so leaning on a core default it changes fails here instead of inside an app.
if ENV['ACTIVE_SUPPORT_LANE']
  require 'active_support'
  require 'active_support/all'
  ActiveSupport.deprecator.behavior = :raise
  ActiveSupport.deprecator.silenced = false
  # A Rails 7.2 app sets this in its generated defaults; left unset, reading it raises a deprecation (SH-B22).
  ActiveSupport.to_time_preserves_timezone = true if ActiveSupport.gem_version < Gem::Version.new('8.0')
end

require 'actionable'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.syntax = :expect }
  config.order = :random
  # Most examples record plain verbs in the middle of a method on purpose; the check has its own spec file.
  config.before(:suite) { Actionable.verb_position_check = false }
  Kernel.srand config.seed
end
