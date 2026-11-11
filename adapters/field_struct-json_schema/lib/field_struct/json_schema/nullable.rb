# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # The optional (nullable) form of a schema (JS-B6, JS-B7). Never mutates its argument.
    module Nullable
      NULL = { 'type' => 'null' }.freeze
      GUARDED_KEYS = %w[enum pattern format].freeze

      module_function

      # Makes +schema+ also accept null.
      #
      # @param schema [::Hash{::String=>::Object}]
      # @return [::Hash{::String=>::Object}]
      def call(schema)
        return schema if schema.empty? || schema.keys == ['x-ruby-type']

        if schema['type'].is_a?(::String) && !schema.key?('$ref')
          widen_type(schema)
        elsif schema.key?('anyOf')
          schema.merge('anyOf' => [*schema['anyOf'], NULL.dup])
        else
          { 'anyOf' => [schema, NULL.dup] }
        end
      end

      # The optional form for a field of +type+: nullable, plus the blank-string alternative for String-family
      # types whose blank strings count as missing and so skip +enum:+/+format:+.
      #
      # @param schema [::Hash{::String=>::Object}]
      # @param type [FieldStruct::Types::Base]
      # @return [::Hash{::String=>::Object}]
      def field(schema, type)
        nullable = call(schema)
        return nullable unless type.is_a?(FieldStruct::Types::String) && GUARDED_KEYS.any? { |key| nullable.key?(key) }

        blank = blank_alternative(type)
        blank ? { 'anyOf' => [nullable, blank.dup] } : nullable
      end

      # @param type [FieldStruct::Types::String]
      # @return [::Hash{::String=>::Object}, nil]
      def blank_alternative(type)
        if type.missing?(' ')
          BLANK_STRING
        elsif type.missing?('')
          EMPTY_STRING
        end
      end

      # @param schema [::Hash{::String=>::Object}]
      # @return [::Hash{::String=>::Object}]
      def widen_type(schema)
        widened = schema.merge('type' => [schema['type'], 'null'])
        widened['enum'] = [*schema['enum'], nil] if schema.key?('enum')
        widened
      end
    end
  end
end
