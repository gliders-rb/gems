# frozen_string_literal: true

# RuboCop's namespace; this gem adds one cop under it.
module RuboCop
  # RuboCop's cops.
  module Cop
    # This gem's cops.
    module Actionable
      # Flags plain recording verbs (+fail+, +fail_with+, +skip+, +succeed+) that are not the last thing a step does.
      # They record the outcome and keep running; the bang forms stop. The analysis is the same Prism-based walk the
      # first-run check uses; Prism reports byte offsets, which are mapped to character positions in the buffer here.
      #
      # @example
      #   # bad
      #   def charge
      #     fail(:declined) if card.declined?
      #     capture
      #   end
      #
      #   # good
      #   def charge
      #     fail!(:declined) if card.declined?
      #     capture
      #   end
      class VerbNotLast < Base
        # The offense message; +%<verb>s+ is the offending verb.
        #
        # @return [String]
        MSG = '`%<verb>s` records the outcome and keeps running, and more code runs after it: ' \
              "use `%<verb>s!` to stop here, or make it the method's last expression."
        # Class names that count as action bases when the file does not define them.
        #
        # @return [Array<String>]
        DEFAULT_BASES = %w[Actionable::Action ApplicationAction].freeze

        # Runs once per file; offenses come from the Prism analysis, not from RuboCop's own AST.
        #
        # @return [void]
        def on_new_investigation
          source = processed_source.buffer.source
          result = ::Actionable::VerbPosition.parse(source)
          return unless result

          scan = ::Actionable::VerbPosition::ClassScan.new(result.value, base_classes)
          offenses = scan.checked_defs.flat_map { |node| ::Actionable::VerbPosition.offenses_in(node) }
          offenses.uniq(&:start_offset).sort_by(&:start_offset).each do |offense|
            add_offense(range_for(source, offense), message: format(MSG, verb: offense.verb))
          end
        end

        private

        def base_classes
          Array(cop_config['ActionBaseClasses'] || DEFAULT_BASES).map { |name| name.to_s.delete_prefix('::') }
        end

        # Prism offsets are bytes; the buffer indexes characters.
        def range_for(source, offense)
          first = source.byteslice(0, offense.start_offset).length
          last = first + source.byteslice(offense.start_offset, offense.byte_length).length
          Parser::Source::Range.new(processed_source.buffer, first, last)
        end
      end
    end
  end
end
