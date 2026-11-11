# frozen_string_literal: true

module Actionable
  module Tools
    # Builds the JSON Schema of an action's input, minus the fields the server fills from context (AT-B10, AT-B11).
    module InputSchema
      module_function

      # @param input [Class] the action's input struct class
      # @param context_fields [Array<::Symbol>] field names taken from context
      # @return [::Hash{::String=>::Object}] a fresh schema (draft 2020-12), context fields removed under their JSON names
      def build(input, context_fields)
        schema = FieldStruct::JSONSchema.generate(input)
        keys = FieldStruct::Introspection.properties(input).select { |property| context_fields.include?(property.field.name) }
        keys.each { |property| remove(schema, property.key) }
        schema
      end

      # @param schema [::Hash{::String=>::Object}]
      # @param key [::String]
      # @return [void]
      def remove(schema, key)
        schema['properties']&.delete(key)
        return unless schema['required']

        schema['required'].delete(key)
        schema.delete('required') if schema['required'].empty?
      end
    end
  end
end
