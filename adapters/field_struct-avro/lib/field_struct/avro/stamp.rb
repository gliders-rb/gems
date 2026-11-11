# frozen_string_literal: true

module FieldStruct
  module Avro
    # What a cached result was built from, for one struct class: its fields (compared by identity, a redeclared
    # field is a new object), the identity of its +serialize+ mapping for the format and its class name (AV-B52).
    class Stamp
      # @param klass [::Class]
      # @param serialization [::Symbol]
      # @return [Stamp] the class as it is now
      def self.of(klass, serialization)
        new(klass, serialization, klass.metadata.to_a, klass.metadata.serialization(serialization), klass.name)
      end

      # @param klass [::Class]
      # @param serialization [::Symbol]
      # @param fields [::Array<FieldStruct::Field>]
      # @param mapping [::Hash]
      # @param name [::String, nil]
      def initialize(klass, serialization, fields, mapping, name)
        @klass = klass
        @serialization = serialization
        @fields = fields
        @mapping = mapping
        @name = name
        freeze
      end

      # @return [::Boolean] whether the class still looks the way it did
      def fresh?
        now = @klass.metadata
        @name == @klass.name && @mapping.equal?(now.serialization(@serialization)) && same_fields?(now)
      end

      private

      def same_fields?(metadata)
        index = 0
        metadata.each do |field|
          return false unless @fields[index].equal?(field)

          index += 1
        end
        index == @fields.size
      end
    end
  end
end
