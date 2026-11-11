# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Turns a struct into a message instance (PB-B40..B42).
    class Encoder
      # @param serialization [::Symbol]
      def initialize(serialization)
        @serialization = serialization
      end

      # @param struct [FieldStruct::Base] an instance of a checked struct class
      # @return [::Object] a message instance
      def call(struct)
        klass = struct.class
        hash = {}
        Properties.for(klass, @serialization).each do |property|
          value = struct.public_send(property.field.name)
          hash[property.key] = node_value(property.node, value, property.key) unless value.nil?
        end
        Registry.message_class(klass, @serialization).new(hash)
      end

      private

      def node_value(node, value, key)
        case node
        when Introspection::ArrayNode then value.map { |item| element(node.element, item, key) }
        when Introspection::StructNode then call(value)
        else scalar(node.type, value, key)
        end
      end

      def element(node, item, key)
        raise ::ArgumentError, "#{key}: protobuf repeated fields can't hold nil" if item.nil?

        node_value(node, item, key)
      end

      def scalar(type, value, key)
        case type
        when Types::Binary then value.b
        when Types::BigDecimal then value.to_s('F')
        when Types::Date then value.iso8601
        when Types::Time, Types::DateTime then timestamp(value)
        when Types::Value then Google::Protobuf::Value.from_ruby(JsonValue.call(value, key))
        when Types::String, Types::Symbol then value.to_s
        else value
        end
      end

      def timestamp(value)
        time = value.respond_to?(:to_time) ? value.to_time : value
        Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
      end
    end
  end
end
