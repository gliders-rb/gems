# frozen_string_literal: true

module Actionable
  module Job
    # Include into a Sidekiq or ActiveJob class to run actions with the right retry behaviour.
    module Mixin
      # @return [Actionable::Result, nil] the result of the last {#run_actionable}
      attr_reader :actionable_result

      # Runs the action; raises {RetryableFailure} when the result should be retried.
      #
      # @param action_class [Class]
      # @return [Actionable::Result] on ack or discard
      # @raise [Actionable::Job::RetryableFailure]
      def run_actionable(action_class, *, **)
        @actionable_result = action_class.run(*, **)
        honor = action_class.respond_to?(:honor_retry_metadata?) && action_class.honor_retry_metadata?
        disposition = Job.disposition(@actionable_result, permanent: actionable_permanent_codes, honor_retry: honor)
        raise RetryableFailure, @actionable_result if disposition == :retry

        @actionable_result
      end

      # Override to change which failure codes are discarded.
      #
      # @return [Array<Symbol>]
      def actionable_permanent_codes
        DEFAULT_PERMANENT_CODES
      end
    end
  end
end
