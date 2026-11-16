# frozen_string_literal: true

# The ActiveSupport lane (rake spec:active_support, SH-B22): ActiveSupport loads before the gem and its
# deprecations raise, so leaning on a core default it changes fails here instead of inside an app.
if ENV['ACTIVE_SUPPORT_LANE']
  require 'active_support'
  require 'active_support/all'
  ActiveSupport.deprecator.behavior = :raise
  ActiveSupport.deprecator.silenced = false
end

require 'field_struct/avro'

# FIELD_STRUCT_AVRO_NATIVE=1 runs the whole suite with the optional Rust encoder from the sibling
# field_struct-avro-native gem (compiled there first with `bundle exec rake compile`). This gem does not depend on it.
if ENV['FIELD_STRUCT_AVRO_NATIVE'] == '1'
  $LOAD_PATH.unshift(File.expand_path('../../field_struct-avro-native/lib', __dir__))
  require 'field_struct/avro/native'
  raise 'FIELD_STRUCT_AVRO_NATIVE=1 but the native encoder is not enabled' unless FieldStruct::Avro::Native.enabled?

  warn 'field_struct-avro specs: native encoder enabled'
end

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
  config.before { FieldStruct::Avro.clear_cache }
end
