# frozen_string_literal: true

module FieldStruct
  module Types
    # Raw bytes: a copy of the text tagged ASCII-8BIT. Whitespace is data; only nil and empty are missing.
    class Binary < String
      # @param value [::Object]
      # @return [::String, nil] a binary copy; the input is never changed
      def coerce(value, **)
        text = super
        text&.b
      end

      # @param value [::Object]
      # @return [Boolean] true for nil and the empty string
      def missing?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
