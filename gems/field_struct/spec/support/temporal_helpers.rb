# frozen_string_literal: true

# Helpers shared by the temporal specs.
module TemporalHelpers
  # Builds a class with one field +v+ of the given type and returns a lambda: value -> field value.
  def reader(type, **options)
    klass = Class.new(FieldStruct::Base) { field :v, type, **options }
    ->(input) { klass.new(v: input).v }
  end

  def build(type, **options)
    Class.new(FieldStruct::Base) { field :v, type, **options }
  end

  def errors_of(type, input, **)
    build(type, **).new(v: input).errors[:v]
  end

  # Runs the block with the process zone set to +zone+.
  def with_process_zone(zone)
    previous = ENV.fetch('TZ', nil)
    ENV['TZ'] = zone
    yield
  ensure
    ENV['TZ'] = previous
  end
end

RSpec.configure do |config|
  config.include TemporalHelpers
  config.around(:each, :denver) { |example| with_process_zone('America/Denver') { example.run } }
end
