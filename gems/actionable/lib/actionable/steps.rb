# frozen_string_literal: true

require_relative 'steps/base'
require_relative 'steps/method'
require_relative 'steps/action'
require_relative 'steps/case'

module Actionable
  # Step objects: one entry in an action's pipeline.
  module Steps
    # Builds the step object for a +step+ declaration target.
    #
    # @param target [Symbol, String, Class] a method name or an Action subclass
    # @param options [Object] +if:+ / +unless:+ and friends
    # @return [Steps::Base]
    # @raise [ArgumentError] for any other target
    def self.build(target, **options)
      refusal = "unsupported step target: #{target.inspect}"
      return Method.new(target.to_sym, **options) if target.is_a?(Symbol) || target.is_a?(String)
      raise ArgumentError, refusal unless target.is_a?(Class) && target <= Actionable::Action

      Steps::Action.new(target, **options)
    end
  end
end
