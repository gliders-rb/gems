# frozen_string_literal: true

module FieldStruct
  module Avro
    # Argument checking shared by every public function (AV-B1, AV-B2).
    module Check
      module_function

      # Validates in the documented order and returns the serialization as a Symbol.
      #
      # @param klass [::Object] the class to check
      # @param timestamp [::Symbol, nil] nil skips the check (+from_datum+ has none)
      # @param serialization [::Symbol, ::String]
      # @param bytes [::Object] checked for +decode+ only (pass +NOT_GIVEN+ to skip)
      # @return [::Symbol] the serialization
      # @raise [::ArgumentError] for the first bad argument
      def call(klass, serialization:, timestamp: nil, bytes: NOT_GIVEN)
        struct_class!(klass)
        timestamp!(timestamp) unless timestamp.nil?
        serialization = serialization!(serialization)
        bytes!(bytes) unless bytes.equal?(NOT_GIVEN)
        serialization
      end

      # Marks "no bytes argument" (nil is not a valid +bytes+ either).
      NOT_GIVEN = ::Object.new.freeze

      # @param klass [::Object]
      # @return [void]
      def struct_class!(klass)
        return if klass.is_a?(::Class) && klass < FieldStruct::Base

        raise ::ArgumentError, "FieldStruct::Avro expects a FieldStruct::Base subclass, got #{klass.inspect}"
      end

      # @param timestamp [::Object]
      # @return [void]
      def timestamp!(timestamp)
        return if TIMESTAMPS.include?(timestamp)

        raise ::ArgumentError, "FieldStruct::Avro timestamp: must be one of #{TIMESTAMPS.inspect}, got #{timestamp.inspect}"
      end

      # @param serialization [::Object]
      # @return [::Symbol]
      def serialization!(serialization)
        serialization = serialization.to_sym if serialization.is_a?(::String)
        return serialization if serialization.is_a?(::Symbol)

        raise ::ArgumentError, "FieldStruct::Avro expects serialization: to be a Symbol, got #{serialization.inspect}"
      end

      # @param bytes [::Object]
      # @return [void]
      def bytes!(bytes)
        return if bytes.is_a?(::String)

        raise ::ArgumentError, "FieldStruct::Avro.decode expects the bytes as a String, got #{bytes.class}"
      end

      # The root of a schema must be assigned to a constant (AV-B2).
      #
      # @param klass [::Class]
      # @return [void]
      def named!(klass)
        return if FieldStruct::Introspection.named?(klass)

        raise ::ArgumentError, 'FieldStruct::Avro needs a named class for the root record; assign it to a constant'
      end
    end
  end
end
