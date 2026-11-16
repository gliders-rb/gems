# frozen_string_literal: true

module Actionable
  module Docs
    # The Markdown page of one action, in the AD-B10 order.
    # @api private
    class Page
      # The page's last line.
      #
      # @return [String]
      FOOTER = "_Generated from the action's declarations by actionable-docs. Edit the action, not this page._"
      # The hook lists in page order, with their lead-in words.
      #
      # @return [Hash{Symbol=>String}]
      HOOKS = { on_success: 'When it succeeds', on_failure: 'When it stops', on_skip: 'When it finishes early',
                after_commit: 'After the database commits', always: 'Every time, at the end' }.freeze

      # @param action [Class] a named action
      def initialize(action)
        @action = action
        @info = action.describe
      end

      # @return [String] the page, ending with one newline
      def to_s
        parts = ["# #{Words.title(@action)}"]
        parts << @info[:description] if @info[:description]
        parts << "```mermaid\n#{Flowchart.new(@action)}```"
        parts << steps
        parts.push(*[codes('It can stop because', @info[:failures]), codes('It can finish early because', @info[:skips]),
                     hooks, fields('What it needs', @info[:input]), fields('What it produces', @info[:output]),
                     calls].compact)
        parts << FOOTER
        "#{parts.join("\n\n")}\n"
      end

      private

      def steps
        entries = Array(@info[:steps])
        return "## Steps\n\nIt has no steps." if entries.empty?

        lines = entries.each_with_index.map { |entry, index| step_line(entry, index + 1) }
        "## Steps\n\n#{lines.join("\n")}"
      end

      def step_line(entry, number)
        return "#{number}. #{label(entry)}#{Words.guard_suffix(entry[:guard])}" unless entry[:type] == :case

        head = "#{number}. Depending on #{Words.lower_first(Words.plain_label(entry))}#{Words.guard_suffix(entry[:guard])}:"
        branches = Array(entry[:branches]).map { |branch| branch_line(Words.on_words(branch[:on]), branch[:step]) }
        branches << branch_line('anything else', entry[:default]) if entry[:default]
        [head, *branches].join("\n")
      end

      def branch_line(words, entry)
        "   - #{words}: #{label(entry)}#{Words.guard_suffix(entry[:guard])}"
      end

      # A step's words, with a child action as a link to its page.
      def label(entry)
        child = entry[:name]
        return Words.plain_label(entry) unless child.is_a?(Class)

        "[#{entry[:description] || Words.title(child)}](#{Words.link(@action, child)})"
      end

      def codes(heading, declarations)
        return nil if declarations.empty?

        lines = declarations.map do |code, declaration|
          words = declaration[:description] || declaration[:message] || Words.humanize(code)
          retry_note = { true => ' _(worth retrying)_', false => " _(don't retry)_" }[declaration[:metadata][:retry]]
          "- **#{Words.humanize(code)}**: #{words}#{retry_note} `#{code}`"
        end
        "## #{heading}\n\n#{lines.join("\n")}"
      end

      def hooks
        lines = HOOKS.filter_map do |kind, lead|
          entries = @info[:hooks].fetch(kind, [])
          next if entries.empty?

          "- #{lead}: #{entries.map { |entry| "#{label(entry)}#{Words.guard_suffix(entry[:guard])}" }.join(', ')}"
        end
        lines.empty? ? nil : "## What happens after\n\n#{lines.join("\n")}"
      end

      def fields(heading, schema)
        return nil if schema.nil? || schema.empty?
        return "## #{heading}\n\nIt takes one of several input shapes." if schema.key?(:discriminated_on)

        rows = schema.map do |name, field|
          meaning = field[:description] ? field[:description].to_s.gsub('|', '\|') : '—'
          "| #{Words.humanize(name)} | #{meaning} | #{field[:required] ? 'yes' : 'no'} |"
        end
        "## #{heading}\n\n| Field | Meaning | Required |\n|---|---|---|\n#{rows.join("\n")}"
      end

      def calls
        children = Array(@info[:calls])
        return nil if children.empty?

        lines = children.map { |child| "- [#{Words.title(child)}](#{Words.link(@action, child)}) (found in source)" }
        "## Also runs\n\n#{lines.join("\n")}"
      end
    end
  end
end
