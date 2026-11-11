# frozen_string_literal: true

module FieldStruct
  module Types
    # Whole numbers. Strings are base 10 unless +base:+ says otherwise; floats truncate.
    class Integer < Base
      # Largest integer part, in decimal digits, accepted from a BigDecimal.
      # @return [::Integer]
      MAX_DECIMAL_DIGITS = 4300

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          {
            in: option(type: [::Array, ::Range]),
            base: option(type: ::Integer),
            strict: option(type: [::TrueClass, ::FalseClass])
          }
        end
      end

      class << self
        # Checks that +base:+ names a usable radix.
        #
        # @param options [::Hash{::Symbol=>::Object}]
        # @return [::Hash{::Symbol=>::Object}]
        # @raise [ArgumentError] when +base:+ is outside 2..36
        def resolve_options(options, **)
          base = options[:base]
          return options if base.nil? || (2..36).cover?(base)

          raise ::ArgumentError, "base: on Integer expects an Integer from 2 to 36, got #{base}"
        end
      end

      # @param value [::Object]
      # @param base [::Integer, nil] radix for String input (default 10)
      # @param strict [Boolean, nil] accept only whole numbers
      # @return [::Integer, nil]
      # @raise [ArgumentError, TypeError] when the value cannot be read
      def coerce(value, base: nil, strict: false, **)
        return nil if value.nil?
        return parse_string(value, base || 10) if value.is_a?(::String)

        guard_number(value)
        strict ? whole_number(value) : convert(value)
      end

      # @return [::Class]
      def ruby_type
        ::Integer
      end

      private

      def parse_string(text, radix)
        Integer(text, radix, exception: false) ||
          raise(::ArgumentError, "Integer fields expect a base-#{radix} integer, got a String that is not one")
      end

      def guard_number(value)
        return unless value.is_a?(::Float) || value.is_a?(::BigDecimal)

        raise ::ArgumentError, "Integer fields expect a finite number, got a non-finite #{value.class}" unless value.finite?
        return unless value.is_a?(::BigDecimal) && value.exponent > MAX_DECIMAL_DIGITS

        raise ::ArgumentError, "Integer fields read a decimal of at most #{MAX_DECIMAL_DIGITS} digits, got a larger BigDecimal"
      end

      def convert(value)
        Integer(value)
      rescue ::RangeError, ::ArgumentError
        raise ::ArgumentError, "Integer fields could not read #{class_phrase(value)} as a number", cause: nil
      end

      def whole_number(value)
        result = value.is_a?(::Numeric) ? attempt(value) : nil
        return result if result && result == value

        raise ::ArgumentError,
              "Integer fields with strict: true expect a whole number, got #{class_phrase(value)} that is not one"
      end

      def attempt(value)
        Integer(value)
      rescue ::RangeError, ::ArgumentError, ::TypeError
        nil
      end
    end
  end
end
