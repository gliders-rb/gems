# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # What a cached schema depends on in one class (JS-B41): its name, its +unknown_attributes+, its Field objects
    # and its +serialize+ mapping for the format, the latter two compared by identity.
    class Stamp
      # Reads the stamp of +klass+ now.
      #
      # @param klass [::Class]
      # @param serialization [::Symbol]
      # @return [Stamp]
      def self.of(klass, serialization)
        metadata = klass.metadata
        new(klass.name, klass.unknown_attributes, metadata.to_a, metadata.serialization(serialization))
      end

      # @param name [::String, nil]
      # @param unknown [::Symbol]
      # @param fields [::Array<FieldStruct::Field>]
      # @param mapping [::Hash{::Symbol=>::Object}]
      def initialize(name, unknown, fields, mapping)
        @name = name
        @unknown = unknown
        @fields = fields
        @mapping = mapping
        freeze
      end

      # Compares with the class as it is now, without building a second stamp.
      #
      # @param klass [::Class]
      # @param serialization [::Symbol]
      # @return [::Boolean] whether nothing the schema depends on changed
      def current?(klass, serialization)
        metadata = klass.metadata
        @name == klass.name && @unknown == klass.unknown_attributes && @mapping.equal?(metadata.serialization(serialization)) &&
          same_fields?(metadata)
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
