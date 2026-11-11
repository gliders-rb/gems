# frozen_string_literal: true

module FieldStruct
  module Types
    # Symbols. Strings are interned with +to_sym+; anything else is refused.
    class Symbol < Base
      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          { enum: option(type: ::Array) }
        end
      end

      # @param value [::Object]
      # @return [::Symbol, nil]
      # @raise [TypeError] for anything but a Symbol or String
      def coerce(value, **)
        case value
        when nil, ::Symbol then value
        when ::String then value.to_sym
        else raise ::TypeError, "expected Symbol or String, got #{value.class}"
        end
      end

      # @return [::Class]
      def ruby_type
        ::Symbol
      end
    end
  end
end
