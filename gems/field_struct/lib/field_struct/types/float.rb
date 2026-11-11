# frozen_string_literal: true

module FieldStruct
  module Types
    # Floating point numbers. Refuses NaN, infinities and hex strings; +round:+ rounds half up.
    class Float < Base
      # Matches a hexadecimal-looking string, which Float() would accept.
      # @return [::Regexp]
      HEX_PREFIX = /\A\s*[+-]?0x/i
      # Matches a number written with a trailing dot, such as +"5."+.
      # @return [::Regexp]
      TRAILING_DOT = /\A(\s*[+-]?\d[\d_]*)\.(\s*)\z/

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
      # @param round [::Integer, nil] decimal places, half up; may be zero or negative
      # @return [::Float, nil]
      # @raise [ArgumentError, TypeError] when the value cannot be read
      def coerce(value, round: nil, **)
        return nil if value.nil?

        number = to_float(value)
        places = round || self.class.default_round
        places ? number.round(places, half: :up).to_f : number
      end

      # @return [::Class]
      def ruby_type
        ::Float
      end

      private

      def to_float(value)
        number = value.is_a?(::String) ? from_string(value) : from_other(value)
        return number if number.finite?

        raise ::ArgumentError, "Float fields expect a finite number, got a non-finite #{value.class}"
      end

      def from_string(text)
        raise ::ArgumentError, 'Float fields expect a base-10 number, got a String that is not one' if text.match?(HEX_PREFIX)

        Float(text.sub(TRAILING_DOT) { "#{Regexp.last_match(1)}.0#{Regexp.last_match(2)}" }, exception: false) ||
          raise(::ArgumentError, 'Float fields could not read a String as a number')
      end

      def from_other(value)
        Float(value)
      rescue ::RangeError, ::ArgumentError
        raise ::ArgumentError, "Float fields could not read #{class_phrase(value)} as a number", cause: nil
      end
    end
  end
end
