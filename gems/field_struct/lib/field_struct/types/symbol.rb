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

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param _options [::Hash{::Symbol=>::Object}] unused: this type takes no options
      # @return [::Symbol, nil]
      # @api private
      def coerce_positional(value, _options)
        coerce(value)
      end

      # @return [::Class]
      def ruby_type
        ::Symbol
      end
    end
  end
end
