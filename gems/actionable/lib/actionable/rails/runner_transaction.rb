# frozen_string_literal: true

module Actionable
  module Rails
    # Runs the whole run (hooks included) inside the model's transaction when the action is transactional.
    module RunnerTransaction
      # @return [Actionable::Result]
      def run
        setting = @instance.class.transaction_config
        return super unless setting

        store = store_class(setting[:model])
        outcome = nil
        store.transaction(**savepoint_options(store, setting[:options])) do
          outcome = super()
          raise Rollback, outcome if outcome.failure?
        end
        outcome
      rescue Rollback => e
        e.result
      end

      private

      def store_class(model)
        return model if model.is_a?(Class)

        model.to_s.camelize.constantize
      end

      # An action run inside an open transaction takes a savepoint unless +requires_new:+ was given.
      def savepoint_options(store, given)
        return given if given.key?(:requires_new)
        return given unless store.respond_to?(:connection) && store.connection.transaction_open?

        given.merge(requires_new: true)
      end
    end
  end
end
