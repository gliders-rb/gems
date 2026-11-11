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

      # @return [::Class]
      def ruby_type
        ::Object
      end
    end
  end
end
