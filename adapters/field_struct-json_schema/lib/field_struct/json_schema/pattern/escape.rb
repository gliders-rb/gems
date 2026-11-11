# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    module Pattern
      # Escape sequences shared by the translator and the character-class reader (JS-B52, JS-B53). Internal.
      module Escape
        # Characters whose escape (+\.+) means the same in Ruby and in an ECMA-262 pattern under the +u+ flag.
        SYNTAX = %w[^ $ \\ . * + ? ( ) [ ] { } | /].freeze
        # The letter escapes that stand for one control character.
        CONTROL = { 'n' => "\n", 'r' => "\r", 't' => "\t", 'f' => "\f", 'v' => "\v" }.freeze

        module_function

        # Reads the digits of +\x+, +\u+ or the letter of +\c+, which start at +pos+ in +source+.
        #
        # @param letter [::String] +x+, +u+ or +c+
        # @param source [::String]
        # @param pos [::Integer] the position right after the letter
        # @return [Array(::String, ::String), nil] the escape text as written and the character it stands for; nil when the
        #   escape is malformed or has no exact equivalent (+\xHH+ at or above 0x80 is a raw byte in Ruby)
        def numeric(letter, source, pos)
          case letter
          when 'x' then hex(letter, source[pos, 2], 0x7F)
          when 'u' then hex(letter, source[pos, 4], 0xFFFF)
          when 'c' then control(source[pos])
          end
        end

        # @param letter [::String]
        # @param digits [::String, nil]
        # @param limit [::Integer]
        # @return [Array(::String, ::String), nil]
        def hex(letter, digits, limit)
          return nil unless digits&.size == (letter == 'x' ? 2 : 4) && digits.match?(/\A\h+\z/)

          code = digits.to_i(16)
          return nil if code > limit

          ["\\#{letter}#{digits}", [code].pack('U')]
        rescue ::ArgumentError, ::RangeError
          nil
        end

        # @param letter [::String, nil]
        # @return [Array(::String, ::String), nil]
        def control(letter)
          return nil unless letter&.match?(/\A[A-Za-z]\z/)

          ["\\c#{letter}", (letter.ord & 0x1f).chr]
        end

        # @param char [::String, nil]
        # @return [::Boolean] whether +char+ is an ASCII letter or digit (an escape of one has a meaning of its own)
        def alphanumeric?(char)
          !char.nil? && char.match?(/\A[A-Za-z0-9]\z/)
        end
      end
    end
  end
end
