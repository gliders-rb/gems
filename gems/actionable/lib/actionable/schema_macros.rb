# frozen_string_literal: true

module Actionable
  # Class-level +input+, +input_for+ and +output+ declarations and their readers.
  module SchemaMacros
    # Declares the output schema, or reads it when no block is given.
    #
    # @yield a FieldStruct DSL body
    # @return [Class, nil] the schema class
    # @raise [Actionable::DefinitionError] for a field named like a result attribute or method
    def output(&block)
      @output_schema = SchemaBuilder.output(self, &block) if block
      output_schema
    end

    # Declares the typed input schema, or reads it when no block is given.
    #
    # @yield a FieldStruct DSL body
    # @return [Class, nil]
    def input(&block)
      @input_schema = SchemaBuilder.input(&block) if block
      input_schema
    end

    # Picks the input schema at run time from one keyword.
    #
    # @param discriminator [Symbol, String]
    # @yield the branches, with +on(value, Schema)+ and +default(Schema)+
    # @return [Actionable::InputDispatch]
    def input_for(discriminator, &block)
      @input_dispatch = InputDispatch.define(discriminator, &block)
    end

    # @return [Class, nil]
    def output_schema = @output_schema

    # @return [Class, nil]
    def input_schema = @input_schema

    # @return [Actionable::InputDispatch, nil] nil whenever +input_for+ was not used
    def input_dispatch = @input_dispatch
  end
end
