# frozen_string_literal: true

module Actionable
  # Builds the anonymous FieldStruct classes behind +input+ and +output+ blocks.
  module SchemaBuilder
    # Extended onto an output schema while its block runs: collects reserved field names instead of declaring them.
    module Guard
      %i[field required optional].each do |macro|
        define_method(macro) do |name, type, **options|
          return reserved_names << name.to_sym if SchemaBuilder.reserved?(name)

          super(name, type, **options)
        end
      end

      # @return [Array<Symbol>] the reserved names the block tried to declare
      def reserved_names
        @reserved_names ||= []
      end
    end

    class << self
      # An input schema: the block is a plain FieldStruct body.
      #
      # @param block [Proc]
      # @return [Class]
      def input(&block)
        Class.new(FieldStruct::Base, &block)
      end

      # An output schema: refuses names that would collide with the result (AC-B#reservedout).
      #
      # @param owner [Class] the action, for the message
      # @param block [Proc]
      # @return [Class]
      # @raise [Actionable::DefinitionError]
      def output(owner, &block)
        schema = Class.new(FieldStruct::Base)
        schema.extend(Guard)
        schema.class_eval(&block)
        clashes = schema.reserved_names
        unless clashes.empty?
          raise DefinitionError, "#{Actionable.label_for(owner)}: output field(s) #{clashes.map(&:inspect).join(', ')} " \
                                 'conflict with reserved result attributes / methods / instance variables; rename them'
        end
        schema
      end

      # @param name [Symbol, String]
      # @return [Boolean] whether a result already answers to +name+
      def reserved?(name)
        reserved_names.include?(name.to_sym)
      end

      private

      def reserved_names
        @reserved_names ||= (Result.reserved_method_names + %i[result input]).freeze
      end
    end
  end
end
