# frozen_string_literal: true

module FieldStruct
  # A format-neutral, read-only walk of a struct's fields for code that exports a struct to another schema
  # language. The walk reports declarations and nothing else: policy (null, defaults, pass-through options,
  # type mapping) belongs to the exporter. Nodes keep the type instance and options they came from.
  module Introspection
    # One field with its external key and its node.
    class Property
      # @return [FieldStruct::Field]
      attr_reader :field
      # @return [String] the external name for the chosen serialization
      attr_reader :key
      # @return [ScalarNode, ArrayNode, UnionNode, StructNode]
      attr_reader :node

      # @param field [FieldStruct::Field]
      # @param key [String]
      # @param node [ScalarNode, ArrayNode, UnionNode, StructNode]
      def initialize(field, key, node)
        @node = node
        @key = key
        @field = field
        freeze
      end
    end

    # A scalar (or any non-composite) type with the options it is checked with.
    class ScalarNode
      # @return [FieldStruct::Types::Base]
      attr_reader :type
      # @return [Hash{Symbol=>Object, nil}] read-only
      attr_reader :options

      # @param type [FieldStruct::Types::Base]
      # @param options [Hash{Symbol=>Object, nil}]
      def initialize(type, options)
        @options = options
        @type = type
        freeze
      end
    end

    # An array; its element node is built on first read.
    class ArrayNode
      # @return [FieldStruct::Types::Array]
      attr_reader :type
      # @return [Hash{Symbol=>Object, nil}] the options the array was declared with; +{}+ for an array inside an array or union
      attr_reader :options

      # @param type [FieldStruct::Types::Array]
      # @param options [Hash{Symbol=>Object, nil}]
      # @param element_builder [Proc] returns the element node or nil; called at most once
      def initialize(type, options, element_builder)
        @lazy = Lazy.new(element_builder)
        @options = options
        @type = type
        freeze
      end

      # @return [ScalarNode, ArrayNode, StructNode, nil] nil when the element type is unknown or a union (FS-B146)
      def element
        @lazy.value
      end

      # Memoizes one value outside the frozen node (a frozen object cannot set an ivar later).
      class Lazy
        # @param builder [Proc] returns the value; called at most once
        def initialize(builder)
          @value = nil
          @done = false
          @builder = builder
        end

        # @return [ScalarNode, ArrayNode, StructNode, nil]
        def value
          unless @done
            @value = @builder.call
            @done = true
          end
          @value
        end
      end
      private_constant :Lazy
    end

    # A union; one node per member.
    class UnionNode
      # @return [FieldStruct::Types::Union]
      attr_reader :type
      # @return [Array<ScalarNode, ArrayNode, UnionNode, StructNode>] frozen, in declared order
      attr_reader :members

      # @param type [FieldStruct::Types::Union]
      # @param members [Array<ScalarNode, ArrayNode, UnionNode, StructNode>]
      def initialize(type, members)
        @members = members.freeze
        @type = type
        freeze
      end
    end

    # A nested struct, by reference.
    class StructNode
      # @return [FieldStruct::Types::Nested]
      attr_reader :type
      # @return [Class] the struct class
      attr_reader :klass

      # @param type [FieldStruct::Types::Nested]
      # @param klass [Class]
      def initialize(type, klass)
        @klass = klass
        @type = type
        freeze
      end
    end

    class << self
      # One Property per field of +klass+, in declaration order.
      #
      # @param klass [Class] a +FieldStruct::Base+ subclass
      # @param serialization [Symbol, String] the format whose +serialize+ mapping names the keys
      # @return [Array<Property>] a new Array of new objects each call
      def properties(klass, serialization: :json)
        meta = klass.metadata
        renames = meta.serialization(serialization)
        meta.map do |field|
          external = (renames[field.name] || field.name).to_s
          Property.new(field, external, node(field.type_instance, field.options))
        end
      end

      # The node for a type instance checked with an options Hash.
      #
      # @param type [FieldStruct::Types::Base] a type instance (any other object gives a ScalarNode)
      # @param options [Hash{Symbol=>Object, nil}]
      # @return [ScalarNode, ArrayNode, UnionNode, StructNode]
      def node(type, options = {})
        case type
        when Types::Array then ArrayNode.new(type, options, -> { element_node(options) })
        when Types::Union then UnionNode.new(type, type.member_types.map { |member| node(member) })
        when Types::Nested then StructNode.new(type, type.struct_class)
        else ScalarNode.new(type, options)
        end
      end

      # Whether the class can serve as a definition key or title.
      #
      # @param klass [Class]
      # @return [Boolean] false for anonymous classes and classes under an anonymous module
      def named?(klass)
        label = klass.name
        return false if label.nil?

        !label.include?('#<')
      end

      private

      def element_node(options)
        declared = options[:of_type]
        return if declared.nil?

        if declared.is_a?(::Class)
          return if declared <= Types::Union

          declared = declared.new
        end
        node(declared, options[:element] || {})
      end
    end
  end
end
