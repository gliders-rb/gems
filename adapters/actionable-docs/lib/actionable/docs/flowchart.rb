# frozen_string_literal: true

module Actionable
  module Docs
    # The Mermaid flowchart of one action: the happy path top to bottom, decisions for guards and case steps, each
    # child action one linked box, and one exit node per declared failure or skip (AD-B20..AD-B24).
    # @api private
    class Flowchart
      # @param action [Class] a named action
      def initialize(action)
        @action = action
        @info = action.describe
        @lines = ['flowchart TD', '  start([Start])']
        @count = 0
      end

      # @return [String] the chart text, ending with a newline
      def to_s
        tails = Array(@info[:steps]).reduce([['start', nil]]) { |open, entry| step(entry, open) }
        @lines << '  done([Done])'
        connect(tails, 'done')
        exits
        "#{@lines.join("\n")}\n"
      end

      private

      # Adds +entry+ after the +open+ ends; returns the ends the next step hangs off, as +[node, edge label]+ pairs.
      def step(entry, open)
        guard = entry[:guard] || {}
        skipped = []
        { if: %w[yes no], unless: %w[no yes] }.each do |key, (run, skip)|
          next unless guard.key?(key)

          decision = add('g', "{\"#{escape(Words.guard_words(guard[key]))}?\"}")
          connect(open, decision)
          open = [[decision, run]]
          skipped << [decision, skip]
        end
        body(entry, open) + skipped
      end

      def body(entry, open)
        return case_body(entry, open) if entry[:type] == :case

        node = box(entry)
        connect(open, node)
        [[node, nil]]
      end

      def box(entry)
        child = entry[:name]
        return add('s', "[\"#{escape(Words.plain_label(entry))}\"]") unless child.is_a?(Class)

        node = add('s', "[[\"#{escape(entry[:description] || Words.title(child))}\"]]")
        @lines << "  click #{node} \"#{Words.link(@action, child)}\""
        node
      end

      def case_body(entry, open)
        decision = add('c', "{\"#{escape(Words.plain_label(entry))}?\"}")
        connect(open, decision)
        ends = Array(entry[:branches]).flat_map { |branch| step(branch[:step], [[decision, Words.on_words(branch[:on])]]) }
        fallback = entry[:default]
        ends + (fallback ? step(fallback, [[decision, 'anything else']]) : [[decision, 'anything else']])
      end

      def exits
        { failures: %w[f Stops], skips: ['k', 'Finishes early'] }.each do |key, (prefix, verb)|
          @info[key].each_key do |code|
            node = add(prefix, "[/\"#{verb}: #{escape(Words.humanize(code))}\"/]")
            @lines << "  start -->|any step| #{node}"
          end
        end
      end

      def add(prefix, shape)
        @count += 1
        node = "#{prefix}#{@count}"
        @lines << "  #{node}#{shape}"
        node
      end

      def connect(open, target)
        open.each do |from, label|
          @lines << (label ? "  #{from} -->|#{escape(label).tr('|', '/')}| #{target}" : "  #{from} --> #{target}")
        end
      end

      def escape(text)
        text.to_s.tr('"', "'")
      end
    end
  end
end
