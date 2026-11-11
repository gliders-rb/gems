# frozen_string_literal: true

# Builds a FieldStruct class and gives it a constant name (stub_const), so Avro record names exist (SH-B53).
module StructHelpers
  def define_struct(name, parent = FieldStruct::Base, &)
    klass = Class.new(parent, &)
    stub_const(name, klass)
    klass
  end

  def avro_schema(klass, **)
    FieldStruct::Avro.schema(klass, **)
  end

  def field_of(schema, name)
    schema.fetch('fields').find { |field| field['name'] == name }
  end

  def type_of(klass, name, **)
    field_of(avro_schema(klass, **), name).fetch('type')
  end
end

RSpec.configure { |config| config.include StructHelpers }
