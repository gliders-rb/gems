# frozen_string_literal: true

# The ActiveSupport lane (rake spec:active_support, SH-B22): ActiveSupport loads before the gem and its
# deprecations raise, so leaning on a core default it changes fails here instead of inside an app.
if ENV['ACTIVE_SUPPORT_LANE']
  require 'active_support'
  require 'active_support/all'
  ActiveSupport.deprecator.behavior = :raise
  ActiveSupport.deprecator.silenced = false
end

require 'field_struct/protobuf'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
end
