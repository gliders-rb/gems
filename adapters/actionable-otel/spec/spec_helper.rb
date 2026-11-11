# frozen_string_literal: true

require 'logger'
require 'stringio'
ENV['OTEL_TRACES_EXPORTER'] = 'none'
ENV['OTEL_LOG_LEVEL'] = 'fatal'

require 'opentelemetry/sdk'
require 'actionable/otel'
require 'actionable/rspec'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

OTEL_EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
OpenTelemetry::SDK.configure do |c|
  c.logger = Logger.new(StringIO.new)
  c.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(OTEL_EXPORTER))
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed

  config.before { OTEL_EXPORTER.reset }
  config.after do
    Actionable::Otel.step_spans = true
    Actionable::Otel.exception_details = :type_only
  end
end
