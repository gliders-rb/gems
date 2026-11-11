# frozen_string_literal: true

module Actionable
  module Steps
    # Abstract step: a name, the declaration options and a guard check. Equality is class plus name only.
    class Base
      # @return [Symbol, Class] the method name, or the child action class
      attr_reader :name

      # @return [Hash{Symbol=>Object}] the options given at declaration, frozen (Array, Hash and String values too)
      attr_reader :options

      # @param name [Symbol, Class]
      # @param options [Object]
      def initialize(name, **options)
        @options = freeze_options(options)
        @name = name
        @guarded = options.key?(:if) || options.key?(:unless)
      end

      # @return [Symbol]
      def kind = :step

      # Performs the step.
      #
      # @param _instance [Actionable::Action]
      # @return [Object]
      # @raise [NotImplementedError] on the abstract base
      def call(_instance)
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      # @return [Array<Symbol>] the instance methods the run-start check demands
      def required_methods = []

      # @param instance [Actionable::Action]
      # @return [Boolean] whether an +if:+ or +unless:+ guard opts this step out
      def skip?(instance)
        return false unless @guarded

        positive = options.fetch(:if, nil)
        negative = options.fetch(:unless, nil)
        return true if options.key?(:if) && !evaluate_guard(positive, instance)

        options.key?(:unless) && evaluate_guard(negative, instance) ? true : false
      end

      # @param other [Object]
      # @return [Boolean] same concrete class and same name
      def ==(other)
        other.instance_of?(self.class) && other.name == name
      end

      alias eql? ==

      # @return [Integer]
      def hash
        [self.class, name].hash
      end

      private

      # Freezes the option Hash and copies of its Array, Hash and String values (the caller's own objects stay
      # unfrozen), so nothing declared can change after the guard flag and the action-step memos are taken.
      def freeze_options(options)
        options.each { |key, value| options[key] = deep_frozen(value) }
        options.freeze
      end

      def deep_frozen(value)
        case value
        when Array then value.map { |item| deep_frozen(item) }.freeze
        when Hash then value.transform_values { |item| deep_frozen(item) }.freeze
        when String then value.frozen? ? value : value.dup.freeze
        else value
        end
      end

      def evaluate_guard(guard, instance)
        return guard.call(instance) if guard.respond_to?(:call)

        instance.__send__(guard)
      end
    end
  end
end
