# frozen_string_literal: true

module Actionable
  module Rails
    # Class macros: declare that an action runs inside a database transaction.
    module Transactions
      # Wraps every run in +model.transaction(**options)+.
      #
      # @param model [Class, Symbol, String] the model whose connection owns the transaction
      # @param options [Object] passed to +transaction+ verbatim
      # @return [Hash{Symbol=>Object}] the stored config
      def transactional(model:, **options)
        @transaction_config = { model: model, options: options }
      end

      # @return [Hash{Symbol=>Object}, nil] +{model:, options:}+ from the nearest class that declared one, +nil+ when none did
      def transaction_config
        return @transaction_config if instance_variable_defined?(:@transaction_config)

        superclass.respond_to?(:transaction_config) ? superclass.transaction_config : nil
      end
    end
  end
end
