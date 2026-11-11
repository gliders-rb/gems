# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    module Pattern
      # One element of a translated sequence: an atom, an anchor, a group or a lookaround, with its quantifier. The
      # translator builds these and renders them back to text; the safety analysis reads them (JS-B60..B63). Internal.
      class Item
        # @return [::Symbol] +:atom+, +:anchor+, +:start+ (+\A+), +:group+ or +:look+
        attr_reader :kind
        # @return [::Integer] the characters it can match (CharSet); 0 for an anchor or lookaround
        attr_reader :set
        # @return [::Array<::Array<Item>>, nil] a group's or lookaround's alternatives
        attr_reader :alternatives
        # @return [::String, nil] the lower-case ASCII letter of a one-letter atom (case folding bookkeeping)
        attr_reader :letter
        # @return [::Integer] the fewest repetitions
        attr_reader :min
        # @return [::Integer, ::Float] the most repetitions (Float::INFINITY when unbounded)
        attr_reader :max
        # @return [::String] the quantifier text as emitted, lazy mark included
        attr_reader :quantifier

        # @param kind [::Symbol]
        # @param body [::String, nil] the atom text, or a group's opening such as +(?:+
        # @param set [::Integer]
        # @param alternatives [::Array<::Array<Item>>, nil]
        # @param letter [::String, nil]
        def initialize(kind:, body:, set: 0, alternatives: nil, letter: nil)
          @kind = kind
          @body = body
          @set = set
          @alternatives = alternatives
          @letter = letter
          @min = 1
          @max = 1
          @quantifier = ''
        end

        # @return [::Boolean] whether a quantifier may follow
        def quantifiable?
          %i[atom group].include?(@kind)
        end

        # Applies a quantifier.
        #
        # @param min [::Integer]
        # @param max [::Integer, ::Float]
        # @param text [::String]
        # @return [void]
        def quantify(min, max, text)
          @min = min
          @max = max
          @quantifier = text
        end

        # @return [::String] the translated text of this item
        def text
          return "#{@body}#{@quantifier}" unless @alternatives

          "#{@body}#{Item.render(@alternatives)})#{@quantifier}"
        end

        # @param alternatives [::Array<::Array<Item>>]
        # @return [::String]
        def self.render(alternatives)
          alternatives.map { |sequence| sequence.map(&:text).join }.join('|')
        end
      end
    end
  end
end
