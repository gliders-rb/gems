# frozen_string_literal: true

module Actionable
  # The step option keys a declaration may use: the core ones plus the ones adapters registered (AC-B#stepoptions).
  # @api private
  module StepOptions
    # The keys the core reads.
    #
    # @return [Array<Symbol>]
    CORE = %i[if unless input expose desc].freeze

    module_function

    # Raises when +step+ carries a key nothing reads, or a +desc:+ that is not a String.
    #
    # @param action [Class] the declaring action
    # @param step [Actionable::Steps::Base]
    # @param registered [Hash{Symbol=>String}] the registered keys
    # @param label [String] the step's label in messages
    # @return [void]
    # @raise [Actionable::DefinitionError] for an unknown key
    # @raise [ArgumentError] for a +desc:+ that is not a String
    def check!(action, step, registered, label)
      check_desc!(action, step, label)
      unknown = step.options.each_key.find { |key| !CORE.include?(key) && !registered.key?(key) }
      return unless unknown

      known = (CORE + registered.keys).map(&:to_s).sort
      clause = FieldStruct::Suggestion.clause(unknown, known, sigil: '', suffix: ':')
      clause = " (known: #{known.map { |key| "#{key}:" }.join(', ')})" if clause.empty?
      raise DefinitionError, "unknown step option #{unknown}: on #{Actionable.label_for(action)}##{label}#{clause}"
    end

    # @param action [Class]
    # @param step [Actionable::Steps::Base]
    # @param label [String]
    # @return [void]
    # @raise [ArgumentError] for a +desc:+ that is not a String
    def check_desc!(action, step, label)
      return unless step.options.key?(:desc)

      desc = step.options[:desc]
      raise ArgumentError, "#{Actionable.label_for(action)}##{label}: desc: takes a String, got #{desc.class}" unless desc.is_a?(String)
    end
  end
end
