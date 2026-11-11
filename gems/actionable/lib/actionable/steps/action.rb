# frozen_string_literal: true

module Actionable
  module Steps
    # Runs another action class, threading parent instance variables in and child output fields back.
    class Action < Base
      # @param name [Class] the child action class
      # @param options [Object] +if:+ / +unless:+, +input:+ and +expose:+
      def initialize(name, **options)
        super
        @input_ivars = Array(@options[:input]).map { |field| [field.to_sym, :"@#{field}"].freeze }.freeze
        @expose = @options[:expose]&.map(&:to_sym)&.freeze
      end

      # @return [Symbol]
      def kind = :action

      # Runs the child with the +input:+ ivars as keywords, then absorbs or adopts its result.
      #
      # @param instance [Actionable::Action] the parent
      # @return [Hash{Symbol=>Object}, nil] the absorbed fields (incidental), nil when the child failed
      def call(instance)
        child = name.run(**input_keywords(instance))
        Measurement.adopt_child_history(child.history)
        instance.__send__(:take_child_result, child, expose)
      end

      private

      # The +input:+ fields as +[name, :@name]+ pairs and the +expose:+ names as Symbols (nil when not given)
      # are worked out once, in +initialize+, so a frozen step runs too.
      attr_reader :input_ivars, :expose

      def input_keywords(instance)
        keywords = {}
        input_ivars.each { |field, ivar| keywords[field] = instance.instance_variable_get(ivar) }
        keywords
      end
    end
  end
end
