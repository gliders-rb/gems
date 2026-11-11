# frozen_string_literal: true

require_relative '../char_set'

module FieldStruct
  module JSONSchema
    module Pattern
      module Safety
        # JS-B60: a quantifier whose maximum is more than 1 on a group that can split one input many ways is refused,
        # unless the group is unambiguous. Internal.
        module Groups
          module_function

          # @param alternatives [::Array<::Array<Item>>]
          # @return [void]
          def check(alternatives)
            alternatives.each { |sequence| sequence.each { |item| visit(item) } }
          end

          # @param item [Item]
          # @return [void]
          def visit(item)
            return unless item.alternatives

            throw :unsafe if item.max > 1 && repeating?(item) && !unambiguous?(item)
            check(item.alternatives)
          end

          # A group is repeating when it holds a variable-count quantifier or an alternation, directly or in a nested group.
          #
          # @param group [Item]
          # @return [::Boolean]
          def repeating?(group)
            group.alternatives.size > 1 || group.alternatives.any? do |sequence|
              sequence.any? { |item| item.min != item.max || (item.alternatives && repeating?(item)) }
            end
          end

          # @param group [Item]
          # @return [::Boolean]
          def unambiguous?(group)
            alternatives = group.alternatives
            return false unless alternatives.all? { |sequence| plain?(sequence) }

            firsts = alternatives.map { |sequence| first_set(sequence) }
            return false unless disjoint_all?(firsts)

            every = firsts.reduce(0, :|)
            alternatives.all? { |sequence| steady?(sequence, every) }
          end

          # Not empty, not made only of items that match nothing, and no group or lookaround inside.
          def plain?(sequence)
            !sequence.all? { |item| nullable?(item) } && sequence.none?(&:alternatives)
          end

          # Every variable-count item must be disjoint from what can follow it.
          def steady?(sequence, every)
            sequence.each_with_index.all? do |item, index|
              item.min == item.max || item.set.nobits?(follow_first(sequence, index, every))
            end
          end

          # @return [::Boolean] whether the item can match nothing (an empty count, or a zero-width item)
          def nullable?(item)
            item.min.zero? || %i[anchor start look].include?(item.kind)
          end

          # What a sequence can start with, looking past leading nullable items.
          def first_set(sequence)
            set = 0
            sequence.each do |item|
              set |= item.set
              break unless nullable?(item)
            end
            set
          end

          # What can come right after sequence[index]: the items after it up to the first required one, plus, when all of
          # them can match nothing, whatever the next iteration of the group can start with.
          def follow_first(sequence, index, every)
            set = 0
            sequence[(index + 1)..].each do |item|
              set |= item.set
              return set unless nullable?(item)
            end
            set | every
          end

          def disjoint_all?(sets)
            sets.combination(2).all? { |a, b| a.nobits?(b) }
          end
        end
      end
    end
  end
end
