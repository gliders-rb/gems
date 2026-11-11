# frozen_string_literal: true

module Actionable
  module Steps
    # Calls an instance method of the action, public or private.
    class Method < Base
      # @return [Symbol]
      def kind = :method

      # @return [Array<Symbol>]
      def required_methods = [name]

      # @param instance [Actionable::Action]
      # @return [Object] the method's value
      def call(instance)
        instance.__send__(name)
      end
    end
  end
end
