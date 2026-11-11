# frozen_string_literal: true

module Actionable
  module Rails
    # After a Success, hands the action's after-commit hooks to ActiveRecord to run once the outermost commit happens.
    module RunnerAfterCommit
      # @return [Actionable::Result]
      def run
        outcome = super
        defer_to_commit(@instance) if outcome.success?
        outcome
      end

      private

      # Registers the hook batch with ActiveRecord, or does nothing when the action has none.
      def defer_to_commit(target)
        owner = target.class
        return unless owner.respond_to?(:after_commit_hooks)

        batch = owner.after_commit_hooks.to_a
        return if batch.empty?

        ::ActiveRecord.after_all_transactions_commit { drain_commit_hooks(target, batch) }
      end

      # The run is over: guards are read now, a halting verb stops only the remaining hooks, nothing is recorded.
      def drain_commit_hooks(target, batch)
        Actionable.catch_halt do
          batch.each do |hook|
            next if hook.skip?(target)

            hook.call(target)
          end
        end
      end
    end
  end
end
