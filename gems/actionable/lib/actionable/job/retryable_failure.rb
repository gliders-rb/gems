# frozen_string_literal: true

module Actionable
  module Job
    # Raised by {Mixin#run_actionable} when the disposition is +:retry+, so the queue's own retry machinery takes over.
    class RetryableFailure < Actionable::Error
      # @return [Actionable::Result]
      attr_reader :result

      # @param result [Actionable::Result] the failure (or retried skip)
      def initialize(result)
        @result = result
        verb = result.failure? ? 'failed' : 'skipped'
        super("actionable run #{verb} with retryable code #{result.code.inspect}")
      end
    end
  end
end
