# frozen_string_literal: true

# Dev-only checks over the generated signature file and Sord's log (FS L17). Pure functions: the rake tasks in
# rakelib/sigs.rake do the running; this module decides what counts as a failure. Not packaged with the gem.
module SigGuards
  ANSI = /\e\[[0-9;]*m/
  WARNING = /\A\[(?:OMIT|DUCK)\s*\]/
  LOCATION = / \S+\.rb:\d+:/
  UNRESOLVED = /\s(\S+) wasn't able to be resolved to a constant/

  module_function

  # Counts the word +untyped+ on lines that are not comments.
  #
  # @param paths [Array<String>] signature files
  # @return [Integer]
  def count_untyped(paths)
    Array(paths).sum do |path|
      File.readlines(path).sum do |line|
        line.lstrip.start_with?('#') ? 0 : line.scan(/\buntyped\b/).size
      end
    end
  end

  # Compares the count with the committed ceiling. It must be equal: above means new untyped crept in, below
  # means the ceiling should be lowered so the gain cannot be lost.
  #
  # @return [String, nil] a failure message, or nil when they match
  def untyped_failure(count:, ceiling:)
    return nil if count == ceiling

    if count > ceiling
      "sig/ has #{count} `untyped` (ceiling #{ceiling}): #{count - ceiling} new. " \
        'Type the new ones (fix the YARD tags and run `rake sigs:generate`) rather than raising the ceiling.'
    else
      "sig/ has #{count} `untyped` (ceiling #{ceiling}): #{ceiling - count} fewer. " \
        "Lower the ceiling in support/untyped_ceiling.txt to #{count} so the gain is kept."
    end
  end

  # The +[OMIT]+ and +[DUCK]+ lines of Sord's log, with colour and the +file.rb:LINE:+ position removed, unique and sorted.
  #
  # @param output [String] Sord's combined output
  # @return [Array<String>]
  def sord_warnings(output)
    output.gsub(ANSI, '').lines.map(&:chomp).grep(WARNING).map { |line| line.sub(LOCATION, '') }.uniq.sort
  end

  # Names Sord could not resolve (YARD types that do not name a loaded constant).
  #
  # @param output [String] Sord's combined output
  # @return [Array<String>] sorted and unique
  def unresolved_names(output)
    output.gsub(ANSI, '').lines.filter_map { |line| line[UNRESOLVED, 1] }.uniq.sort
  end

  # @param text [String] the allowlist file: one warning per line, blank lines and +#+ lines ignored
  # @return [Array<String>]
  def parse_allowlist(text)
    text.lines.map(&:chomp).reject { |line| line.strip.empty? || line.start_with?('#') }
  end

  # @return [String, nil] lists warnings missing from the allowlist and entries that no longer occur; nil when equal
  def allowlist_failure(warnings:, allowlist:)
    fresh = warnings - allowlist
    stale = allowlist - warnings
    return nil if fresh.empty? && stale.empty?

    parts = []
    unless fresh.empty?
      parts << "New Sord warnings (type them in YARD, or add them to support/sord_allowlist.txt):\n#{fresh.map do |w|
        "  #{w}"
      end.join("\n")}"
    end
    unless stale.empty?
      parts << "Stale allowlist entries (remove them from support/sord_allowlist.txt):\n#{stale.map do |w|
        "  #{w}"
      end.join("\n")}"
    end
    parts.join("\n")
  end
end
