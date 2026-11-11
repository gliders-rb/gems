# frozen_string_literal: true

module Actionable
  module Rails
    # Class macro for hooks that run after the outermost transaction commits (needs ActiveRecord >= 7.2).
    module AfterCommit
      # Declares a hook: a method name or a nested action (+if:+ / +unless:+, and +input:+ for actions).
      #
      # @param target [Symbol, String, Class]
      # @param options [Object]
      # @return [Set<Actionable::Steps::Base>]
      # @raise [Actionable::DefinitionError] without a supported ActiveRecord
      def after_commit(target, **options)
        unless defined?(::ActiveRecord) && ::ActiveRecord.respond_to?(:after_all_transactions_commit)
          raise DefinitionError, 'after_commit needs ActiveRecord >= 7.2 (ActiveRecord.after_all_transactions_commit); ' \
                                 'load a supported ActiveRecord before declaring it'
        end

        upsert(after_commit_hooks, Steps.build(target, **options))
      end

      # @return [Set<Actionable::Steps::Base>] this class's own copy of the after-commit hooks
      def after_commit_hooks = (@after_commit_hooks ||= Set.new)
    end
  end
end
