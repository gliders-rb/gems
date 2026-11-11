# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Builds the +FileDescriptorProto+ of one struct class (PB-B5..B9).
    class DescriptorBuilder
      # @param klass [::Class<FieldStruct::Base>] a checked, named struct class
      # @param serialization [::Symbol] the +serialize+ format that names the fields
      def initialize(klass, serialization)
        @klass = klass
        @serialization = serialization
        @oneofs = []
        @imports = []
      end

      # @return [::Object] a +Google::Protobuf::FileDescriptorProto+
      # @raise [::ArgumentError] for a bad number or name, or a field with no exact mapping
      def call
        properties = Introspection.properties(@klass, serialization: @serialization)
        numbers = Numbers.call(@klass, properties)
        properties.each { |property| field_name!(property.key) }
        unique_names!(properties)
        fields = properties.map { |property| field(property, numbers.fetch(property.key)) }
        message = Google::Protobuf::DescriptorProto.new(name: Names.message_name(@klass), field: fields, oneof_decl: @oneofs)
        Google::Protobuf::FileDescriptorProto.new(
          name: Names.file_name(@klass), package: Names.package(@klass), syntax: 'proto3', dependency: @imports, message_type: [message]
        )
      end

      private

      NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/
      private_constant :NAME

      def field_name!(key)
        return if NAME.match?(key)

        raise ::ArgumentError, "#{@klass}: #{key.inspect} isn't a protobuf field name; " \
                               "rename it with `serialize #{@serialization.inspect}, field: \"name\"`"
      end

      def unique_names!(properties)
        clashes = properties.group_by(&:key).select { |_, group| group.size > 1 }
        return if clashes.empty?

        text = clashes.map do |key, group|
          "fields #{group.map do |p|
            p.field.name
          end.join(', ')} are both named #{key.inspect} in the message"
        end
        raise ::ArgumentError, "#{@klass}: #{text.join('; ')}"
      end

      def field(property, number)
        node = property.node
        repeated = node.is_a?(Introspection::ArrayNode)
        type, type_name = repeated ? element_type(property) : scalar_type(node, property.field)
        attrs = { name: property.key, number: number, type: type, label: repeated ? :LABEL_REPEATED : :LABEL_OPTIONAL }
        attrs[:type_name] = type_name if type_name
        attrs.merge!(explicit_presence(property.key)) unless repeated || type_name
        Google::Protobuf::FieldDescriptorProto.new(**attrs)
      end

      def explicit_presence(key)
        @oneofs << Google::Protobuf::OneofDescriptorProto.new(name: "_#{key}")
        { proto3_optional: true, oneof_index: @oneofs.size - 1 }
      end

      def element_type(property)
        element = property.node.element
        return refuse(property.field, 'an array of unions') if element.nil?
        return refuse(property.field, 'an array of arrays (protobuf has no repeated repeated)') if element.is_a?(Introspection::ArrayNode)

        scalar_type(element, property.field)
      end

      # @return [Array(Symbol, String)] the protobuf type and, for a message, its full name
      def scalar_type(node, field)
        return refuse(field, 'a union') if node.is_a?(Introspection::UnionNode)
        return struct_type(node.klass, field) if node.is_a?(Introspection::StructNode)

        well_known = ScalarTypes.well_known(node.type)
        return message_type(*well_known) if well_known

        [ScalarTypes.type_for(node.type) || refuse(field, "a #{node.type.class} (no protobuf mapping)")]
      end

      def struct_type(klass, field)
        refuse(field, 'an anonymous struct (assign it to a constant)') unless Introspection.named?(klass)

        message_type(Names.full_name(klass), (Names.file_name(klass) unless klass == @klass))
      end

      def message_type(type_name, import)
        @imports << import unless import.nil? || @imports.include?(import)
        [:TYPE_MESSAGE, type_name]
      end

      def refuse(field, what)
        raise ::ArgumentError, "#{@klass}##{field.name} is #{what}, which field_struct-protobuf can't map yet"
      end
    end
  end
end
