# frozen_string_literal: true

module FieldStruct
  module Types
    # Text like {String}, but the result is a frozen copy; the input is never touched.
    class ImmutableString < String
      # @param value [::Object]
      # @return [::String, nil] a frozen copy
      def coerce(value, **)
        text = super
        text&.dup&.freeze
      end

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::String, nil]
      # @api private
      def coerce_positional(value, options)
        super&.dup&.freeze
      end
    end
  end
end
