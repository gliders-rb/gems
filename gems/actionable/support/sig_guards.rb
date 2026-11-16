# frozen_string_literal: true

# Dev-only checks over the generated signature file and Sord's log (AC-B#sigratchet). Pure functions: the rake tasks in
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

  # +Object+ or +::Object+ as a whole name (not +BasicObject+, not +Pottery::Object+).
  LOOSE_OBJECT = /(?<![\w:])(?:::)?Object\b/
  # +top+ where a type goes: after an opening bracket, +|+, +&+, +,+, +->+ or a +:+ (optionally after +?+ for an
  # optional parameter), and not itself a keyword or method name (+top:+).
  LOOSE_TOP = /(?:[(\[|&,:]|->)\s*\??\btop\b(?!\s*:)/
  # A superclass is a real parent, not a loose type: +class Kiln < ::Object+ does not count.
  SUPERCLASS = /^(\s*class\s+\S+\s*<\s*)(?:::)?Object\b/

  # Counts the loose types +Object+ and +top+ on lines that are not comments (the rule: build decision T3 in the
  # gem's spec). Like +untyped+ they accept anything; unlike it some are the honest type (a value of any class), so
  # the ratchet holds today's number rather than asking for zero.
  #
  # @param paths [Array<String>] signature files
  # @return [Integer]
  def count_loose(paths)
    Array(paths).sum do |path|
      File.readlines(path).sum do |line|
        next 0 if line.lstrip.start_with?('#')

        typed = line.sub(SUPERCLASS, '\1')
        typed.scan(LOOSE_OBJECT).size + typed.scan(LOOSE_TOP).size
      end
    end
  end

  # Compares the loose count with its ceiling, the same way as {untyped_failure}.
  #
  # @return [String, nil] a failure message, or nil when they match
  def loose_failure(count:, ceiling:)
    return nil if count == ceiling

    label = "sig/ has #{count} `Object`/`top` types (ceiling #{ceiling})"
    if count > ceiling
      "#{label}: #{count - ceiling} new. Give them a real type (fix the YARD tags and run `rake sigs:generate`) " \
        'rather than raising the ceiling.'
    else
      "#{label}: #{ceiling - count} fewer. Lower the ceiling in support/loose_ceiling.txt to #{count} so the gain is kept."
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

  # What Sord writes for these classes is not valid RBS until the type arguments are added (the fix-ups below).
  ENUMERABLE_ARGUMENTS = { 'Registry' => '[[String, Class]]', 'BatchResult' => '[Actionable::Result]' }.freeze

  # The verbs of AC-B#verbsprivate, in the order verbs.rb defines them.
  VERBS = %w[succeed succeed! fail fail! fail_with fail_with! skip skip! halt!].freeze

  # The verbs are private, so the +--hide-private+ run leaves +module Verbs+ empty. This takes their declarations
  # from a second Sord run that keeps private methods (+full+), joins each onto one line, marks it +private+ and puts
  # it into the empty module, so step bodies type-check against the verbs without exposing them.
  #
  # @param text [String] the +--hide-private+ RBS
  # @param full [String] the RBS of a run without +--hide-private+
  # @param verbs [Array<String>] the method names to carry over
  # @return [String]
  # @raise [RuntimeError] when a verb is missing from +full+, or +text+ has no empty +module Verbs+
  def add_private_verbs(text, full, verbs: VERBS)
    body = full[/^  module Verbs\n(.*?)^  end\n/m, 1].to_s
    members = body.split(/\n[ \t]*\n/).to_h { |chunk| [chunk[/^\s*def ([^:\s]+):/, 1], chunk] }
    missing = verbs - members.keys
    raise "Sord's full run declares no #{missing.join(', ')} in Actionable::Verbs" unless missing.empty?

    declared = verbs.map { |name| private_member(members.fetch(name)) }.join("\n")
    empty = "  module Verbs\n  end\n"
    raise 'the generated sig has no empty module Verbs to fill' unless text.include?(empty)

    text.sub(empty, "  module Verbs\n#{declared}  end\n")
  end

  # @param chunk [String] a member's comment lines and its (possibly multi-line) +def+
  # @return [String] the comments, then the +def+ on one line, marked +private+
  def private_member(chunk)
    comments, definition = chunk.lines.partition { |line| line.lstrip.start_with?('#') }
    signature = definition.map(&:strip).join(' ').gsub('( ', '(').gsub(' )', ')')
    "#{comments.join}    private #{signature}\n"
  end

  # The documented fix-ups applied to Sord's output, in order:
  #
  # 1. +include Enumerable+ gets the element type of the class that includes it (Sord leaves the argument out).
  # 2. A class that subclasses +Struct+ gets +::Struct[::Object]+ (RBS wants the member type; Sord writes none).
  # 3. The framework parents come off (AC-B#rbsshipped): +Railtie+, +RubocopPlugin+ and +VerbNotLast+ lose their
  #    superclass and +ProxyValidator+ its +include ActiveModel::Validations+, so the shipped sig names only
  #    field_struct and prism and loads in an app without Rails or RuboCop. Ruby still has the real parents.
  #
  # @param text [String] generated RBS
  # @return [String]
  def fix_up(text)
    text = fix_enumerables(text)
    text = text.gsub(/^(\s*class \w+) < Struct$/, '\1 < ::Struct[::Object]')
    drop_framework_parents(text)
  end

  # Classes whose framework superclass the shipped sig leaves out, by their name in the generated RBS.
  FRAMEWORK_PARENTS = { 'Railtie' => 'Rails::Railtie', 'RubocopPlugin' => 'LintRoller::Plugin', 'VerbNotLast' => 'Base' }.freeze
  # Framework modules the shipped sig does not include.
  FRAMEWORK_INCLUDES = %w[ActiveModel::Validations].freeze

  # @param text [String] generated RBS
  # @return [String]
  def drop_framework_parents(text)
    FRAMEWORK_PARENTS.each do |name, parent|
      text = text.gsub(/^(\s*class #{name}) < (?:::)?#{Regexp.escape(parent)}$/, '\1')
    end
    FRAMEWORK_INCLUDES.each do |name|
      text = text.gsub(/^\s*include (?:::)?#{Regexp.escape(name)}\n(?:[ \t]*\n)?/, '')
    end
    text
  end

  # @param text [String]
  # @return [String]
  def fix_enumerables(text)
    current = nil
    text.lines.map do |line|
      current = Regexp.last_match(1) if line =~ /^\s*class (\w+)/
      next line unless line.match?(/^\s*include Enumerable$/)

      line.sub('Enumerable', "::Enumerable#{ENUMERABLE_ARGUMENTS.fetch(current)}")
    end.join
  end
end
