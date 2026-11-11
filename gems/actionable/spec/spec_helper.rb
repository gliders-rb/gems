# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start { enable_coverage :branch }
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
