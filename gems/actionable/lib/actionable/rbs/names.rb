# frozen_string_literal: true

module Actionable
  module RBS
    # Naming rules for the generated RBS.
    #
    # @private
    module Names
      VALID_CLASS_NAME = /\A[A-Z][A-Za-z0-9_]*\z/
      SUFFIXES = { '?' => 'Predicate', '!' => 'Bang' }.freeze

      module_function

      # The nearest named ancestor action, or +Actionable::Action+.
      def parent_of(klass)
        klass.ancestors.drop(1).find { |ancestor| ancestor.is_a?(::Class) && ancestor < Actionable::Action && ancestor.name } ||
          Actionable::Action
      end

      # @return [::String] the RBS superclass reference
      def superclass_name(klass)
        "::#{parent_of(klass).name}"
      end

      # A lambda from a result constant (+'Success'+) to the class the action's own class inherits from: the parent's
      # own class when the parent has typed outcomes, else the gem's.
      def base_of(klass)
        parent = parent_of(klass)
        ->(const) { parent != Actionable::Action && parent.typed_outcomes? ? "::#{parent.name}::#{const}" : "::Actionable::#{const}" }
      end

      # +:out_of_stock+ is +OutOfStock+; a +?+ or +!+ suffix reads as +Predicate+ or +Bang+.
      def camel(code)
        text = code.to_s
        suffix = SUFFIXES.fetch(text[-1], '')
        text = text.delete_suffix(text[-1]) unless suffix.empty?
        text.split('_').map { |part| part.sub(/\A[a-z]/, &:upcase) }.join + suffix
      end

      # The class name of a code's output schema, checked for validity.
      #
      # @param kind [Symbol] +:skip+ or +:failure+
      def output_class_name(klass, kind, code)
        name = "#{camel(code)}#{kind == :skip ? 'SkipOutput' : 'FailureOutput'}"
        return name if name.match?(VALID_CLASS_NAME)

        raise ::ArgumentError, "#{klass.name}: #{kind} code #{code.inspect} gives #{name}, which is not a valid RBS class name " \
                               '(it must start with an ASCII capital); rename the code'
      end
    end
  end
end
