# frozen_string_literal: true

module FieldStruct
  module Types
    # Exact decimals. Floats are read with 15 significant digits; +round:+ rounds half up.
    class BigDecimal < Base
      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          { round: option(type: ::Integer), in: option(type: [::Array, ::Range]) }
        end

        # Class-wide rounding places used when a field declares no +round:+.
        #
        # @return [::Integer, nil]
        def default_round
          nil
        end
      end

      # @param value [::Object]
      # @param round [::Integer, nil] decimal places, half up whatever +BigDecimal.mode+ says
      # @return [::BigDecimal, nil]
      # @raise [ArgumentError] when the value cannot be read or is not finite
      def coerce(value, round: nil, **)
        return nil if value.nil?

        number = to_decimal(value)
        raise ::ArgumentError, "BigDecimal fields expect a finite number, got a non-finite #{value.class}" unless number.finite?

        places = round || self.class.default_round
        places ? number.round(places, ::BigDecimal::ROUND_HALF_UP) : number
      end

      # @return [::Class]
      def ruby_type
        ::BigDecimal
      end

      private

      def to_decimal(value)
        case value
        when ::BigDecimal then value
        when ::Float then value.finite? ? BigDecimal(value, 15) : value
        when ::Integer, ::String then parse(value)
        else unreadable(value)
        end
      end

      def parse(value)
        BigDecimal(value.to_s, exception: false) || unreadable(value)
      end

      def unreadable(value)
        raise ::ArgumentError, "BigDecimal fields could not read #{class_phrase(value)} as a number"
      end
    end
  end
end
