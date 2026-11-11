# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # The struct classes a class refers to, as a field or as an array element (PB-B30).
    module References
      module_function

      # @param klass [::Class<FieldStruct::Base>]
      # @param serialization [::Symbol]
      # @return [::Array<::Class>] distinct referenced classes in field order, without +klass+ itself
      def call(klass, serialization)
        found = []
        Introspection.properties(klass, serialization: serialization).each do |property|
          other = target(property.node)
          found << other if other && other != klass && !found.include?(other)
        end
        found
      end

      # @param node [FieldStruct::Introspection::ScalarNode, FieldStruct::Introspection::ArrayNode, FieldStruct::Introspection::StructNode]
      # @return [::Class, nil]
      def target(node)
        node = node.element if node.is_a?(Introspection::ArrayNode)
        node.klass if node.is_a?(Introspection::StructNode)
      end
    end
  end
end
