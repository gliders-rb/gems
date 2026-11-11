# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start { enable_coverage :branch }
end

# The ActiveSupport lane (rake spec:active_support): load ActiveSupport BEFORE the gem and make its
# deprecations fatal, so any dependence on what it redefines shows up as a failure (FS-I6).
if ENV['FIELD_STRUCT_AS']
  require 'active_support'
  require 'active_support/all'
  ActiveSupport.deprecator.behavior = :raise
  ActiveSupport.deprecator.silenced = false
end

require 'field_struct'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
end
