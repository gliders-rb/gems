# frozen_string_literal: true

module Actionable
  # Class-level +measure+ configuration and its queries.
  module MeasureMacros
    # Valid modes of +measure+.
    #
    # @return [Array<Symbol>]
    MEASURE_MODES = %i[all none sampled].freeze

    # Reads or sets the measure mode.
    #
    # @param mode [Symbol, nil] +:all+, +:none+ or +:sampled+; omit to read
    # @param rate [Numeric, nil] required for +:sampled+, between 0 and 1
    # @return [Symbol] the resolved mode
    # @raise [ArgumentError] for an unknown mode or a bad rate
    def measure(mode = nil, rate: nil)
      return @measure_mode || :none if mode.nil?

      raise ArgumentError, "unknown measure mode #{mode.inspect}" unless MEASURE_MODES.include?(mode)

      validate_rate!(rate) if mode == :sampled
      @measure_mode = mode
      @measure_rate = mode == :sampled ? rate : nil
      mode
    end

    # @return [Numeric, nil] the stored sampling rate
    def measure_rate
      @measure_rate
    end

    # @return [Boolean]
    def measure_all? = measure == :all

    # @return [Boolean]
    def measure_sampled? = measure == :sampled

    # @return [Boolean] rolls +rand < rate+ for a sampled action; false otherwise
    def measure_sample_hit?
      measure_sampled? && rand < @measure_rate
    end

    private

    def validate_rate!(rate)
      return if rate.is_a?(Numeric) && rate >= 0 && rate <= 1

      raise ArgumentError, "measure :sampled requires rate: between 0 and 1, got #{rate.inspect}"
    end
  end
end
