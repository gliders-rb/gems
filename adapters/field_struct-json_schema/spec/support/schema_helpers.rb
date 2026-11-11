# frozen_string_literal: true

require 'oj'

# Helpers shared by the generator specs.
module SchemaHelpers
  JS = FieldStruct::JSONSchema

  # Builds a struct class from a block, as a FieldStruct::Base subclass.
  def struct(&)
    Class.new(FieldStruct::Base, &)
  end

  # Validates the canonical JSON of +instance+ against +schema+ with an independent validator.
  def valid_json?(schema, instance)
    JSONSchemer.schema(schema, format: true).valid?(Oj.load(instance.to_json))
  end

  # Validates a parsed JSON value against +schema+.
  def valid_value?(schema, value)
    JSONSchemer.schema(schema, format: true).valid?(value)
  end

  def property(klass, name, **)
    JS.generate(klass, **)['properties'].fetch(name.to_s)
  end
end

RSpec.configure { |config| config.include SchemaHelpers }
