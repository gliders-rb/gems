# frozen_string_literal: true

require_relative 'char_class'
require_relative 'char_set'
require_relative 'escape'
require_relative 'item'

module FieldStruct
  module JSONSchema
    module Pattern
      # The single left-to-right pass over a Regexp source (JS-B52): reads it into a sequence of {Item}s while emitting the
      # ECMA-262 text. Anything without an exact equivalent, or malformed, makes {#call} answer nil. Internal.
      class Translator
        # The letter pairs Ruby folds to one character under +i+ (JS-B54): ss, ff, fi, fl, st.
        MERGES = %w[ss ff fi fl st].freeze
        INTERVAL = /\G\{(\d+)(?:(,)(\d*))?\}/
        BAD_INTERVAL = /\G\{,\d*\}/
        GROUP_NAME = /\G<([A-Za-z_][A-Za-z0-9_]*)>/
        MAX_COUNT = 100_000
        private_constant :MERGES, :INTERVAL, :BAD_INTERVAL, :GROUP_NAME, :MAX_COUNT

        # @return [::Array<::Array<Item>>, nil] the top-level alternatives of the last successful {#call}
        attr_reader :alternatives

        # @param source [::String] a Regexp's source
        # @param fold_case [::Boolean] whether the Regexp has the +i+ option
        def initialize(source, fold_case:)
          @src = source
          @fold = fold_case
          @pos = 0
          @names = []
        end

        # @return [::String, nil] the translated pattern, or nil when there is none
        def call
          return nil if @fold && (!@src.ascii_only? || @src.match?(/ss|ff|fi|fl|st/i))

          catch(:refuse) do
            @alternatives = read_alternatives(0)
            refuse if @pos < @src.size
            Item.render(@alternatives)
          end
        end

        private

        def refuse
          throw :refuse
        end

        def peek(offset = 0)
          @src[@pos + offset]
        end

        def advance
          char = @src[@pos]
          refuse if char.nil?
          @pos += 1
          char
        end

        def take?(text)
          return false unless @src[@pos, text.size] == text

          @pos += text.size
          true
        end

        def read_alternatives(depth)
          alternatives = [[]]
          loop do
            char = peek
            break if char.nil?
            break if char == ')' && depth.positive?

            refuse if char == ')'
            if take?('|')
              alternatives << []
            else
              alternatives.last << read_term(alternatives.last.last, depth)
            end
          end
          alternatives
        end

        def read_term(previous, depth)
          item = read_atom(depth)
          merge_check(previous, item) if @fold
          read_quantifier(item) if item.quantifiable?
          item
        end

        # JS-B54: one-letter atoms side by side that Ruby would fold into one string.
        def merge_check(previous, item)
          return unless previous&.letter && item.letter && previous.quantifier.empty?

          refuse if MERGES.include?("#{previous.letter}#{item.letter}")
        end

        def read_atom(depth)
          char = advance
          case char
          when '\\' then read_escape
          when '[' then read_class
          when '(' then read_group(depth)
          when '*', '+', '?' then refuse
          else read_plain(char)
          end
        end

        def read_plain(char)
          case char
          when '.' then atom('[^\n]', CharSet::DOT)
          when '^' then Item.new(kind: :anchor, body: '(?:^|(?<=\n)(?!$))')
          when '$' then Item.new(kind: :anchor, body: '(?![^\n])')
          when '{' then brace
          when '}', ']' then atom("\\#{char}", CharSet.bit(char))
          else literal(char)
          end
        end

        def atom(text, set, letter: nil)
          Item.new(kind: :atom, body: text, set: set, letter: letter)
        end

        # A { is a literal unless it starts a valid interval, which here has nothing to quantify.
        def brace
          refuse if @src.match?(INTERVAL, @pos - 1) || @src.match?(BAD_INTERVAL, @pos - 1)

          atom('\{', CharSet.bit('{'))
        end

        def literal(char)
          return atom("(?:#{char})", CharSet::NON_ASCII) if char.ord > 0xFFFF
          return folded_letter(char) if @fold && char.match?(/\A[A-Za-z]\z/)

          atom(char, CharSet.bit(char))
        end

        def folded_letter(char)
          extra = CharSet::EXTRAS[char.downcase]
          set = CharSet.bit(char) | CharSet.bit(char.swapcase)
          set |= CharSet::NON_ASCII if extra
          atom("[#{char.downcase}#{char.upcase}#{extra}]", set, letter: char.downcase)
        end

        def read_class
          return take_anything if @src[@pos - 1, 6] == '[\s\S]'

          item, @pos = CharClass.new(@src, @pos, fold_case: @fold).call
          item
        end

        # [\s\S] means "any character" and is identical in both engines.
        def take_anything
          @pos += 5
          atom('[\s\S]', CharSet::ALL)
        end

        def read_escape
          char = advance
          case char
          when 'A' then Item.new(kind: :start, body: '^')
          when 'z' then Item.new(kind: :anchor, body: '$')
          when 's', 'S', 'h', 'H' then shorthand(char)
          when 'd', 'D', 'w', 'W' then atom("\\#{char}", class_set(char))
          when *Escape::CONTROL.keys then atom("\\#{char}", CharSet.bit(Escape::CONTROL.fetch(char)))
          else other_escape(char)
          end
        end

        def class_set(char)
          set = char.downcase == 'd' ? CharSet::DIGIT : CharSet::WORD
          char == char.downcase ? set : CharSet.negate(set)
        end

        def shorthand(char)
          text = { 's' => '[\t\n\v\f\r ]', 'S' => '[^\t\n\v\f\r ]', 'h' => '[0-9a-fA-F]', 'H' => '[^0-9a-fA-F]' }.fetch(char)
          set = char.downcase == 's' ? CharSet::SPACE : CharSet::HEX
          atom(text, char == char.downcase ? set : CharSet.negate(set))
        end

        def other_escape(char)
          case char
          when '0' then zero_escape
          when 'x', 'u', 'c' then numeric(char)
          else punctuation_escape(char)
          end
        end

        def zero_escape
          refuse if peek&.match?(/\A[0-9]\z/)

          atom('\0', CharSet.bit("\0"))
        end

        def punctuation_escape(char)
          refuse if Escape.alphanumeric?(char) || char.ord > 127

          atom(Escape::SYNTAX.include?(char) ? "\\#{char}" : char, CharSet.bit(char))
        end

        def numeric(letter)
          refuse if @fold && letter != 'c'
          text, char = Escape.numeric(letter, @src, @pos) || refuse
          @pos += text.size - 2
          atom(text, CharSet.bit(char))
        end

        def read_group(depth)
          prefix, kind = group_prefix
          alternatives = read_alternatives(depth + 1)
          refuse unless take?(')')

          Item.new(kind: kind, body: prefix, alternatives: alternatives)
        end

        def group_prefix
          return ['(', :group] unless take?('?')
          return ['(?:', :group] if take?(':')

          %w[= ! <= <!].each { |mark| return ["(?#{mark}", :look] if take?(mark) }
          refuse unless (match = @src.match(GROUP_NAME, @pos))

          name = match[1]
          refuse if @names.include?(name)

          @names << name
          @pos += match[0].size
          ["(?<#{name}>", :group]
        end

        def read_quantifier(item)
          min, max, text = quantifier_head
          return unless text

          refuse if @fold && merge_repeat?(item, text, min)

          item.quantify(min, max, quantifier_tail(text))
          refuse if stacked_quantifier?
        end

        # JS-B54: {n}, n >= 2, repeating a one-letter s or f atom, which Ruby may fold into one string.
        def merge_repeat?(item, text, min)
          text.start_with?('{') && min >= 2 && %w[s f].include?(item.letter)
        end

        # Possessive (a*+), stacked (a**, a{2}{3}): different meanings in Ruby and JavaScript.
        def stacked_quantifier?
          peek&.match?(/\A[*+?]\z/) || @src.match?(INTERVAL, @pos) || @src.match?(BAD_INTERVAL, @pos)
        end

        def quantifier_head
          case peek
          when '*' then take_quantifier(0, Float::INFINITY, '*')
          when '+' then take_quantifier(1, Float::INFINITY, '+')
          when '?' then take_quantifier(0, 1, '?')
          when '{' then interval
          end
        end

        def take_quantifier(min, max, text)
          @pos += text.size
          [min, max, text]
        end

        def interval
          match = @src.match(INTERVAL, @pos)
          return nil unless match

          min = Integer(match[1], 10)
          max = interval_max(match, min)
          refuse if min > MAX_COUNT || max < min || (max.finite? && max > MAX_COUNT)

          take_quantifier(min, max, match[0])
        end

        def interval_max(match, min)
          return min unless match[2]
          return Float::INFINITY if match[3].empty?

          Integer(match[3], 10)
        end

        # A lazy ? after the quantifier; {n}? is "optional" in Ruby and lazy in JavaScript, so it is refused.
        def quantifier_tail(text)
          return text unless peek == '?'

          refuse if text.match?(/\A\{\d+\}\z/)
          @pos += 1
          "#{text}?"
        end
      end
    end
  end
end
