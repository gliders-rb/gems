# frozen_string_literal: true

require_relative 'char_set'
require_relative 'escape'
require_relative 'item'

module FieldStruct
  module JSONSchema
    module Pattern
      # Reads a character class +[...]+ (JS-B53) and, under +i+, folds it (JS-B54). Throws +:refuse+ for anything with no
      # exact equivalent. Internal.
      class CharClass
        # One thing in a class: +char+ is set when it is a single character (usable as a range end).
        Member = Struct.new(:text, :set, :char, :escaped)
        private_constant :Member

        # @param source [::String] the whole pattern source
        # @param pos [::Integer] the position right after the +[+
        # @param fold_case [::Boolean]
        def initialize(source, pos, fold_case:)
          @src = source
          @pos = pos
          @fold = fold_case
          @parts = []
          @set = 0
          @letters = []
        end

        # @return [Array(Item, ::Integer)] the class as an atom, and the position after its +]+
        def call
          negated = take?('^')
          refuse if peek == ']'
          read_element until take?(']')
          set = negated ? CharSet.negate(@set) : @set
          letter = negated || @letters.size != 1 ? nil : @letters.first
          [Item.new(kind: :atom, body: "[#{'^' if negated}#{@parts.join}]", set: set, letter: letter), @pos]
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

        def take?(char)
          return false unless peek == char

          @pos += 1
          true
        end

        def read_element
          first = read_member(@parts.empty?)
          if peek == '-' && peek(1) && peek(1) != ']'
            @pos += 1
            add_range(first, read_member(true))
          else
            add_member(first)
          end
        end

        def read_member(range_end)
          char = advance
          case char
          when '[' then refuse
          when '\\' then escape
          when '-' then dash(range_end)
          else plain(char)
          end
        end

        # An unescaped - is literal only as the first or last member (or as the end of a range).
        def dash(allowed)
          refuse unless allowed || peek == ']'
          plain('-')
        end

        def plain(char)
          refuse if char.ord > 0xFFFF || (char == '&' && peek == '&')

          Member.new(char, CharSet.bit(char), char, false)
        end

        def escape
          char = advance
          case char
          when 's' then Member.new('\t\n\v\f\r ', CharSet::SPACE, nil, true)
          when 'h' then Member.new('0-9a-fA-F', CharSet::HEX, nil, true)
          when 'd', 'w', 'D', 'W' then class_escape(char)
          when 'b' then single('\b', "\b")
          when *Escape::CONTROL.keys then single("\\#{char}", Escape::CONTROL.fetch(char))
          when '-', *Escape::SYNTAX then single("\\#{char}", char)
          else other_escape(char)
          end
        end

        def class_escape(char)
          refuse if @fold && %w[D W].include?(char)

          set = char.downcase == 'd' ? CharSet::DIGIT : CharSet::WORD
          Member.new("\\#{char}", char == char.downcase ? set : CharSet.negate(set), nil, true)
        end

        def single(text, char)
          Member.new(text, CharSet.bit(char), char, true)
        end

        def other_escape(char)
          if char == '0'
            refuse if peek&.match?(/\A[0-9]\z/)

            return single('\0', "\0")
          end
          return numeric(char) if %w[x u c].include?(char)

          refuse if Escape.alphanumeric?(char) || char.ord > 127

          single(char, char)
        end

        def numeric(letter)
          refuse if @fold && letter != 'c'
          text, char = Escape.numeric(letter, @src, @pos) || refuse
          @pos += text.size - 2
          single(text, char)
        end

        def add_member(member)
          letter = member.char&.match?(/\A[A-Za-z]\z/) && !member.escaped ? member.char : nil
          if @fold && letter
            @parts << folded(letter)
            @set |= folded_set(letter)
          else
            @parts << member.text
            @set |= member.set
          end
          @letters << letter&.downcase
        end

        def add_range(low, high)
          refuse unless low.char && high.char && low.char.ord <= high.char.ord
          if @fold
            fold_range(low, high)
          else
            @parts << "#{low.text}-#{high.text}"
            @set |= CharSet.range(low.char, high.char)
            @letters << nil
          end
        end

        def fold_range(low, high)
          refuse if low.escaped || high.escaped

          unless covers_letters?(low.char, high.char)
            @parts << "#{low.char}-#{high.char}"
            @set |= CharSet.range(low.char, high.char)
            @letters << nil
            return
          end
          refuse unless same_case_letters?(low.char, high.char)

          add_folded_range(low.char, high.char)
        end

        def covers_letters?(low, high)
          [%w[A Z], %w[a z]].any? { |from, to| low.ord <= to.ord && high.ord >= from.ord }
        end

        def same_case_letters?(low, high)
          [/\A[a-z]\z/, /\A[A-Z]\z/].any? { |kind| low.match?(kind) && high.match?(kind) }
        end

        def add_folded_range(low, high)
          extras = CharSet::EXTRAS.select { |letter, _| (low.downcase..high.downcase).cover?(letter) }.values
          @parts << "#{low}-#{high}#{low.swapcase}-#{high.swapcase}#{extras.join}"
          @set |= CharSet.range(low, high) | CharSet.range(low.swapcase, high.swapcase)
          @set |= CharSet::NON_ASCII unless extras.empty?
          @letters << (low == high ? low.downcase : nil)
        end

        def folded(letter)
          "#{letter}#{letter.swapcase}#{CharSet::EXTRAS[letter.downcase]}"
        end

        def folded_set(letter)
          set = CharSet.bit(letter) | CharSet.bit(letter.swapcase)
          CharSet::EXTRAS.key?(letter.downcase) ? set | CharSet::NON_ASCII : set
        end
      end
    end
  end
end
