# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Turns a message instance into a struct (PB-B51..B53).
    class Decoder
      # @param serialization [::Symbol]
      def initialize(serialization)
        @serialization = serialization
      end

      # @param klass [::Class<FieldStruct::Base>] a checked struct class
      # @param message [::Object] a message instance of the class's message
      # @return [FieldStruct::Base]
      def call(klass, message)
        descriptor = message.class.descriptor
        attrs = {}
        Properties.for(klass, @serialization).each do |property|
          attrs[property.field.name] = property_value(property, descriptor.lookup(property.key), message)
        end
        klass.new(attrs)
      end

      private

      def property_value(property, field, message)
        node = property.node
        return field.get(message).map { |item| item_value(node.element, item) } if node.is_a?(Introspection::ArrayNode)
        return nil unless field.has?(message)

        item_value(node, field.get(message))
      end

      def item_value(node, item)
        return call(node.klass, item) if node.is_a?(Introspection::StructNode)

        case node.type
        when Types::Time, Types::DateTime then Zone.apply(::Time.at(item.seconds, item.nanos, :nsec, in: 'UTC'), node.options[:zone])
        when Types::Value then item.to_ruby(true)
        else item
        end
      end
    end
  end
end
