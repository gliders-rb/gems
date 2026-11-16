# frozen_string_literal: true

module FieldStruct
  module Types
    # No coercion at all: the escape hatch.
    class Value < Base
      # @param value [::Object]
      # @return [::Object] the input, untouched
      def coerce(value, **)
        value
      end

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param _options [::Hash{::Symbol=>::Object}] unused: this type takes no options
      # @return [::Object]
      # @api private
      def coerce_positional(value, _options)
        coerce(value)
      end

      # @return [::Class]
      def ruby_type
        ::Object
      end
    end
  end
end
