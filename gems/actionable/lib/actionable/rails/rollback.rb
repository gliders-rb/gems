# frozen_string_literal: true

module Actionable
  module Rails
    # Raised inside a transactional run to roll it back when the run ended in a Failure; swallowed outside the block.
    class Rollback < StandardError
      # @return [Actionable::Result] the failure the run ended with
      attr_reader :result

      # @param result [Actionable::Result, nil]
      def initialize(result = nil)
        @result = result
        super('actionable run failed; rolling back')
      end
    end
  end
end
