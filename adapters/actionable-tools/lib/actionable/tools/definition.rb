# frozen_string_literal: true

module Actionable
  module Tools
    # Form-neutral description of one action as a tool: name, description, annotations, schemas and +call+.
    # Immutable once built (AT-I7).
    class Definition
      # @return [Class] the action
      attr_reader :action
      # @return [::String]
      attr_reader :name
      # @return [::String] as given, not stripped
      attr_reader :description
      # @return [::Hash{::Symbol=>Boolean}] frozen
      attr_reader :annotations
      # @return [::Hash{::String=>::Object}] JSON Schema of the arguments the model sends; frozen (shallowly)
      attr_reader :input_schema
      # @return [::Hash{::String=>::Object}] JSON Schema of the result envelope {Tools::RESULT_KEYS}; frozen (shallowly)
      attr_reader :output_schema

      # @param action [Class] an +Actionable::Action+ subclass
      # @param description [::String]
      # @param name [::String, nil]
      # @param context [::Hash{::Symbol=>::Proc}]
      # @param annotations [::Hash{::Symbol=>Boolean}] frozen in place (the caller's Hash)
      # @raise [::ArgumentError] when the action cannot be a tool (AT-B1..B5)
      def initialize(action, description:, name:, context:, annotations:)
        check_shape(action, description)
        @action = action
        @context = normalise_context(action, context)
        @name = name || default_name(action)
        @description = description
        @annotations = annotations.freeze
        @input_schema = InputSchema.build(action.input_schema, @context.keys).freeze
        @output_schema = OutputSchema.build(action).freeze
        freeze
      end

      # Runs the action for a model's arguments and returns the six-key result envelope (AT-B20, AT-B21). Exceptions
      # the action raises propagate (AT-B22).
      #
      # @param arguments [::Hash{::Object=>::Object}] what the model sent, under external (JSON) names
      # @param source [Object, nil] handed to each context proc
      # @return [::Hash{::String=>::Object}] status, code, message, output, errors, metadata
      def call(arguments, source = nil)
        Envelope.build(action.run(**run_input(arguments, source)))
      end

      # @param result [::Hash{::String=>::Object}] an envelope from {#call}
      # @return [Boolean] true only for a failure (a skip is not an error)
      def error?(result)
        result['status'] == 'failure'
      end

      private

      def run_input(arguments, source)
        reverse = action.input_schema.metadata.reverse_serialization(:json)
        input = arguments.to_h.transform_keys { |key| reverse.fetch(key.to_s) { key.to_sym } }
        @context.each { |field, filler| input[field] = filler.call(source) }
        input
      end

      def check_shape(action, description)
        if action.respond_to?(:input_dispatch) && !action.input_dispatch.nil?
          raise ArgumentError, "#{action} has a discriminated input (input_for), which has no single schema yet"
        end
        raise ArgumentError, "#{action} has no input schema; tools need one" if action.input_schema.nil?
        raise ArgumentError, "#{action}: a tool needs a description" if description.to_s.strip.empty?
      end

      def normalise_context(action, context)
        context = context.to_h { |field, source| [field.to_sym, source] }
        unknown = context.keys - action.input_schema.attribute_names
        raise ArgumentError, "#{action} has no input field #{unknown.join(', ')} to take from context" unless unknown.empty?

        context.freeze
      end

      def default_name(action)
        raise ArgumentError, 'an anonymous action needs name:' if action.name.nil?

        snake = action.name.split('::').last
        snake = snake.gsub(/([a-z\d])([A-Z])/, '\1_\2')
        snake.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').downcase
      end
    end
  end
end
