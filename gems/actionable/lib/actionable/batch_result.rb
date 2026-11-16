# frozen_string_literal: true

module Actionable
  # The results of {Action.run_each}, in item order.
  class BatchResult
    include Enumerable

    # @return [Array<Actionable::Result>]
    attr_reader :results

    # @param results [Array<Actionable::Result>]
    def initialize(results)
      @results = results.dup.freeze
    end

    # @yieldparam result [Actionable::Result]
    # @return [Enumerator<Actionable::Result>, self]
    def each(&block)
      return to_enum(:each) unless block_given?

      results.each(&block)
      self
    end

    # @param index [Integer]
    # @return [Actionable::Result, nil]
    def [](index)
      results.at(index)
    end

    # @return [Integer]
    def size
      results.length
    end

    alias length size

    # @return [Boolean]
    def empty?
      results.empty?
    end

    # @return [Boolean] every result is ok (vacuously true when empty)
    def all_ok?
      results.all?(&:ok?)
    end

    # @return [Boolean]
    def any_failure?
      results.any?(&:failure?)
    end

    # @return [Boolean] some failed and some did not
    def partial?
      any_failure? && results.any?(&:ok?)
    end

    # filter_map with is_a? narrows the element type for type checkers; select would keep Result.
    # rubocop:disable Style/MapCompactWithConditionalBlock

    # @return [Array<Actionable::Success>]
    def successes
      results.filter_map { |result| result if result.is_a?(Success) }
    end

    # @return [Array<Actionable::Failure>]
    def failures
      results.filter_map { |result| result if result.is_a?(Failure) }
    end

    # @return [Array<Actionable::Skipped>]
    def skips
      results.filter_map { |result| result if result.is_a?(Skipped) }
    end

    # rubocop:enable Style/MapCompactWithConditionalBlock

    # @param id_field [Symbol]
    # @return [Array<Hash{Symbol=>Object}>] each result's +to_api_h+ with its index
    def to_api_h(id_field: :id)
      results.each_with_index.collect do |result, position|
        result.to_api_h(index: position, id_field: id_field)
      end
    end
  end
end
