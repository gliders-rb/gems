# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    module Pattern
      # Sets of characters as Integer bitmasks (JS-B60 model): one bit per ASCII character and one bit for "some
      # non-ASCII character" (all of them counted as one, which can only add overlap). Internal.
      module CharSet
        NON_ASCII = 1 << 128
        ALL = (1 << 129) - 1
        # Ruby folds s to U+017F (long s) and k to U+212A (Kelvin sign) under +i+ (JS-B54).
        EXTRAS = { 's' => 0x017F.chr(::Encoding::UTF_8), 'k' => 0x212A.chr(::Encoding::UTF_8) }.freeze

        module_function

        # @param char [::String] one character
        # @return [::Integer] its bit
        def bit(char)
          char.ord < 128 ? 1 << char.ord : NON_ASCII
        end

        # @param chars [::String] characters
        # @return [::Integer]
        def of(chars)
          chars.each_char.reduce(0) { |set, char| set | bit(char) }
        end

        # @param low [::String]
        # @param high [::String]
        # @return [::Integer] every character from +low+ to +high+
        def range(low, high)
          top = [high.ord, 127].min
          set = low.ord <= top ? ((1 << (top - low.ord + 1)) - 1) << low.ord : 0
          high.ord > 127 ? set | NON_ASCII : set
        end

        # @param set [::Integer]
        # @return [::Integer] the complement; non-ASCII always stays in (a negated class matches other non-ASCII characters)
        def negate(set)
          (ALL & ~set) | NON_ASCII
        end

        DIGIT = range('0', '9')
        WORD = range('a', 'z') | range('A', 'Z') | DIGIT | bit('_')
        SPACE = of("\t\n\v\f\r ")
        HEX = DIGIT | range('a', 'f') | range('A', 'F')
        DOT = ALL & ~bit("\n")
      end
    end
  end
end
