# frozen_string_literal: true

require_relative '../char_set'

module FieldStruct
  module JSONSchema
    module Pattern
      module Safety
        # JS-B61: finds chains of two overlapping pairs of variable-count items in a path, which cost O(n^3) or worse. Internal.
        module Chains
          module_function

          # @param paths [::Array<Paths::Path>]
          # @return [void] throws +:unsafe+ when some path holds a chain
          def check(paths)
            paths.each { |path| throw :unsafe if chain?(path.nodes) }
          end

          # L(i) of JS-B61: 0 unless the node is variable, else the most over earlier nodes j paired with it of
          # 1 + max(L(k), k <= j). A path with any L >= 2 is a chain.
          def chain?(nodes)
            levels = []
            peak = []
            nodes.each_with_index do |node, index|
              level = variable?(node) ? level_of(nodes, index, peak) : 0
              return true if level >= 2

              levels << level
              peak << [peak.last || 0, level].max
            end
            false
          end

          def level_of(nodes, index, peak)
            node = nodes[index]
            through = CharSet::ALL
            best = 0
            (index - 1).downto(0) do |back|
              other = nodes[back]
              best = [best, 1 + peak[back]].max if variable?(other) && pair?(other, node, through)
              through &= pass(other)
              break if through.zero?
            end
            best
          end

          def variable?(node)
            node.low != node.high
          end

          # What a node lets through to the pair spanning it: everything when it can match nothing, else its own set.
          def pass(node)
            node.low.zero? ? CharSet::ALL : node.set
          end

          # Whether characters can move between two variable nodes, given what the nodes between let through.
          def pair?(earlier, later, through)
            if earlier.kind == :whole && later.kind == :whole
              (earlier.starts & later.starts & through).nonzero? && (earlier.ends & later.ends & through).nonzero?
            elsif earlier.kind == :whole
              met?(earlier, later.set & through)
            elsif later.kind == :whole
              met?(later, earlier.set & through)
            else
              (earlier.set & later.set & through).nonzero?
            end
          end

          # One alternative of the group whose required items can each be met by a character in +carried+. An alternative
          # with nothing required is an empty iteration, which moves nothing.
          def met?(whole, carried)
            whole.needs.any? { |needs| !needs.empty? && needs.all? { |need| (need & carried).nonzero? } }
          end
        end
      end
    end
  end
end
