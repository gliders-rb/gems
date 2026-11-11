# frozen_string_literal: true

require_relative '../char_set'

module FieldStruct
  module JSONSchema
    module Pattern
      module Safety
        # JS-B62: expands an alternative sequence into flat paths of nodes, which {Chains} then evaluates. Internal.
        module Paths
          # One thing a path matches: a set of characters with a count. +kind+ is +:atom+ or +:whole+ (a variable-count
          # group taken as one unit, carrying its first and last sets and, per alternative, the sets its iteration must match).
          Node = Struct.new(:kind, :set, :low, :high, :starts, :ends, :needs)
          # A flat path; +ended+ is true once a lookaround body has been entered (what follows starts again elsewhere).
          Path = Struct.new(:nodes, :ended)
          LIMIT = 1024
          COPIES = 3
          # The virtual item of JS-B63: an unanchored pattern may start matching anywhere.
          RETRY = Node.new(:atom, CharSet::ALL, 0, Float::INFINITY).freeze

          module_function

          # @param sequence [::Array<Item>] one top-level alternative
          # @return [::Array<Path>] its paths, each starting with the retry item
          def expand_top(sequence)
            expand(sequence, top: true).map { |path| Path.new([RETRY, *path.nodes], path.ended) }
          end

          # @param sequence [::Array<Item>]
          # @param top [::Boolean] whether the sequence is a top-level alternative (a +\A+ there cuts the retry item off)
          # @return [::Array<Path>]
          def expand(sequence, top:)
            sequence.reduce([Path.new([], false)]) do |paths, item|
              variants = variants_of(item, top)
              variants ? join(paths, variants) : paths
            end
          end

          # @return [::Array<Path>, nil] nil for an item that adds nothing to a path
          def variants_of(item, top)
            case item.kind
            when :atom then [Path.new([Node.new(:atom, item.set, item.min, item.max)], false)]
            when :start then top ? [Path.new([Node.new(:atom, 0, 1, 1)], false)] : nil
            when :group then group_variants(item)
            when :look then look_variants(item)
            end
          end

          # Every path so far followed by every variant; a path that already ended stays as it is.
          def join(paths, variants)
            joined = paths.flat_map do |path|
              next [path] if path.ended

              variants.map { |variant| Path.new(path.nodes + variant.nodes, variant.ended) }
            end
            throw :unsafe if joined.size > LIMIT
            joined.uniq
          end

          # A lookaround adds the path that skips it plus, for each way through its body, a path that ends there.
          def look_variants(item)
            bodies = item.alternatives.flat_map { |sequence| expand(sequence, top: false) }
            [Path.new([], false), *bodies.map { |path| Path.new(path.nodes, true) }]
          end

          # A group is unrolled up to three copies; a variable-count one is also taken whole (and, when unbounded, whole next
          # to one unrolled iteration).
          def group_variants(item)
            iterations = item.alternatives.flat_map { |sequence| expand(sequence, top: false) }
            top_count = item.max.infinite? ? COPIES : [item.max, COPIES].min
            variants = (([item.min, COPIES].min)..top_count).flat_map { |count| copies(iterations, count) }
            variants.concat(whole_variants(item, iterations)) if item.min != item.max
            variants
          end

          def copies(iterations, count)
            count.times.reduce([Path.new([], false)]) { |paths, _| join(paths, iterations) }
          end

          def whole_variants(item, iterations)
            whole = Path.new([whole_node(item)], false)
            return [whole] unless item.max.infinite?

            [whole, *join([whole], iterations), *join(iterations, [whole])]
          end

          def whole_node(item)
            sequences = item.alternatives
            Node.new(:whole, union_of(sequences) { |s| chars_of_sequence(s) }, item.min, item.max,
                     union_of(sequences) { |s| first_of(s) }, union_of(sequences) { |s| first_of(s.reverse) },
                     sequences.map { |s| s.reject { |i| zero_width?(i) || i.min.zero? }.map { |i| chars_of(i) } })
          end

          def union_of(sequences, &)
            sequences.map(&).reduce(0, :|)
          end

          def zero_width?(item)
            %i[anchor start look].include?(item.kind)
          end

          # The union of the characters an item can match (a lookaround matches nothing itself).
          def chars_of(item)
            return 0 if item.kind == :look
            return item.set unless item.alternatives

            item.alternatives.reduce(0) { |set, sequence| set | chars_of_sequence(sequence) }
          end

          def chars_of_sequence(sequence)
            sequence.reduce(0) { |set, item| set | chars_of(item) }
          end

          def first_of(sequence)
            set = 0
            sequence.each do |item|
              set |= chars_of(item)
              break unless item.min.positive? && !zero_width?(item)
            end
            set
          end
        end
      end
    end
  end
end
