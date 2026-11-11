# frozen_string_literal: true

require_relative '../actionable'
require_relative 'job/retryable_failure'
require_relative 'job/mixin'
require_relative 'job/retry_macro'

module Actionable
  # Maps a run's result to what a background job should do with it. Pure Ruby; no queue gem is required.
  module Job
    # Failure codes that no retry can fix.
    #
    # @return [Array<Symbol>]
    DEFAULT_PERMANENT_CODES = %i[invalid_input invalid_output not_found].freeze

    class << self
      # Decides what a job does with +result+.
      #
      # @param result [Actionable::Result]
      # @param permanent [Array<Symbol>] failure codes to discard instead of retry
      # @param honor_retry [Boolean] let a +retry+ metadata key decide on its own
      # @return [Symbol] +:ack+, +:discard+ or +:retry+
      def disposition(result, permanent: DEFAULT_PERMANENT_CODES, honor_retry: false)
        return metadata_verdict(result) if honor_retry && carries_retry_hint?(result)
        return :ack if result.ok?

        permanent.include?(result.code) ? :discard : :retry
      end

      private

      def carries_retry_hint?(result)
        result.respond_to?(:metadata) && result.metadata.key?(:retry)
      end

      def metadata_verdict(result)
        return :retry if result.metadata[:retry]

        result.ok? ? :ack : :discard
      end
    end
  end

  Action.extend(Job::RetryMacro)
end
