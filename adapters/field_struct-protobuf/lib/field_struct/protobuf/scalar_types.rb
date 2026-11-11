# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Maps a scalar type instance to its protobuf type (PB-B5).
    module ScalarTypes
      # Checked in order, so a subclass wins (+Binary+ is a +String+).
      MAPPING = [
        [Types::Binary, :TYPE_BYTES], [Types::String, :TYPE_STRING], [Types::Symbol, :TYPE_STRING],
        [Types::BigDecimal, :TYPE_STRING], [Types::Date, :TYPE_STRING], [Types::Boolean, :TYPE_BOOL],
        [Types::Integer, :TYPE_INT64], [Types::Float, :TYPE_DOUBLE]
      ].freeze
      private_constant :MAPPING

      TIMESTAMP = ['.google.protobuf.Timestamp', 'google/protobuf/timestamp.proto'].freeze
      VALUE = ['.google.protobuf.Value', 'google/protobuf/struct.proto'].freeze
      WELL_KNOWN = [[Types::Time, TIMESTAMP], [Types::DateTime, TIMESTAMP], [Types::Value, VALUE]].freeze
      private_constant :TIMESTAMP, :VALUE, :WELL_KNOWN

      module_function

      # @param type [FieldStruct::Types::Base] a type instance
      # @return [::Symbol, nil] the protobuf type, nil when there is no mapping
      def type_for(type)
        MAPPING.find { |klass, _| type.is_a?(klass) }&.last
      end

      # @param type [FieldStruct::Types::Base] a type instance
      # @return [::Array(::String, ::String), nil] the message's full name and the file to import, nil when not a well-known type
      def well_known(type)
        WELL_KNOWN.find { |klass, _| type.is_a?(klass) }&.last
      end
    end
  end
end
