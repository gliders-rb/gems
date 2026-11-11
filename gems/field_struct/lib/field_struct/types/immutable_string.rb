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
    end
  end
end
