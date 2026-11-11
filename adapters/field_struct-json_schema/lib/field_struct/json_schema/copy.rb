# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # Deep copies of schema values: Hashes, Arrays and Strings are copied, everything else is shared (immutable).
    module Copy
      module_function

      # @param value [::Object]
      # @param freeze [::Boolean] whether the copy is frozen all the way down
      # @return [::Object]
      def deep(value, freeze: false)
        copy = case value
               when ::Hash then value.to_h { |key, item| [deep(key, freeze: freeze), deep(item, freeze: freeze)] }
               when ::Array then value.map { |item| deep(item, freeze: freeze) }
               when ::String then value.dup
               else value
               end
        freeze ? copy.freeze : copy
      end

      # A fresh, mutable copy of a cached schema: every Hash, Array and String is new, everything else is shared
      # (immutable). Hash keys are shared as well: a String key is frozen by the Hash that holds it, so nothing
      # reachable through a key can be changed.
      #
      # @param value [::Object] JSON-shaped data
      # @return [::Object]
      def fresh(value)
        case value
        when ::Hash then value.transform_values { |item| fresh(item) }
        when ::Array then value.map { |item| fresh(item) }
        when ::String then value.dup
        else value
        end
      end
    end
  end
end
