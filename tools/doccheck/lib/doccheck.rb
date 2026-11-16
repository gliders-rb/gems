# frozen_string_literal: true

require 'open3'

# Doc coverage for this monorepo (SH-B70..B76): a public method, option or key that no
# page names in code fails the build. A private dev tool, loaded by path; never published.
module DocCheck
  # Methods every Ruby class has by convention; no page needs to list them.
  CONVENTIONAL = %w[== eql? hash inspect to_s freeze pretty_print method_missing respond_to_missing?].freeze
  FORMS = %i[option key].freeze
  FENCE = /^(```|~~~)[^\n]*\n(.*?)^\1[ \t]*$/m
  INLINE = /`([^`\n]+)`/

  module_function

  # The code in a Markdown text: every fenced block and inline code span, one per line (SH-B70).
  #
  # @param markdown [String]
  # @return [String]
  def code_text(markdown)
    fenced = markdown.scan(FENCE).map { |(_, body)| body }
    prose = markdown.gsub(FENCE, '')
    (fenced + prose.scan(INLINE).flatten).join("\n")
  end

  # Public methods a constant defines itself, from files under +lib+ (SH-B71).
  #
  # @param constant [String] a constant path
  # @param kind [Symbol] +:instance+, +:singleton+, +:both+ or +:macros+
  # @param lib [String] the directory whose methods count
  # @return [Array<String>] sorted names
  def public_methods_of(constant, kind, lib:)
    owner = Object.const_get(constant)
    root = File.expand_path(lib)
    found = []
    found.concat(instance_methods_of(owner, root)) if %i[instance both].include?(kind)
    found.concat(class_methods_of(owner, kind, root)) if %i[singleton both macros].include?(kind)
    found.uniq.sort
  end

  # @api private
  def instance_methods_of(owner, root)
    owner.public_instance_methods(false).select { |m| ours?(owner.instance_method(m), root) }.map(&:to_s)
  end

  # @api private
  def class_methods_of(owner, kind, root)
    names = owner.singleton_class.public_instance_methods(false)
    names |= owner.singleton_class.public_instance_methods - Class.public_instance_methods if kind == :macros
    names.select { |m| ours?(owner.method(m).unbind, root) }.map(&:to_s)
  end

  # @api private
  def ours?(method, root)
    file, line = method.source_location
    return true if file.nil?

    File.expand_path(file).start_with?("#{root}/") && !api_private?(file, line)
  end

  # @api private
  # Whether the comment block right above a definition carries +@api private+ (SH-B71).
  def api_private?(file, line)
    lines = File.readlines(file)
    above = lines[0...(line - 1)].reverse.take_while { |text| text.strip.start_with?('#') }
    above.any? { |text| text.include?('@api private') }
  end

  # Every method of +api+ the text doesn't name in code, as +Const#name+ or +Const.name+ (SH-B71).
  #
  # @param markdown [String]
  # @param api [Array<Array(String, Symbol)>] constant paths with their kind
  # @param lib [String]
  # @param allowlist [Array<String>] bare names, +Const#name+ or +Const.name+
  # @return [Array<String>]
  def unnamed_methods(markdown, api:, lib:, allowlist: [])
    code = code_text(markdown)
    entries(api, lib).reject do |label, method|
      CONVENTIONAL.include?(method) || allowlist.include?(method) || allowlist.include?(label) ||
        word?(code, method.delete_suffix('='))
    end.map(&:first).uniq
  end

  # Allowlist entries that match no method of +api+ (SH-B74).
  #
  # @param allowlist [Array<String>]
  # @param api [Array<Array(String, Symbol)>]
  # @param lib [String]
  # @return [Array<String>]
  def stale_allowlist(allowlist, api:, lib:)
    known = entries(api, lib)
    labels = known.map(&:first)
    names = known.map(&:last)
    allowlist.reject { |entry| labels.include?(entry) || names.include?(entry) }
  end

  # @api private
  # @return [Array<Array(String, String)>] +[label, method]+ pairs
  def entries(api, lib)
    api.flat_map do |constant, kind|
      instance = %i[instance both].include?(kind) ? public_methods_of(constant, :instance, lib: lib) : []
      side = { instance: nil, both: :singleton }.fetch(kind, kind)
      klass = side ? public_methods_of(constant, side, lib: lib) : []
      instance.map { |m| ["#{constant}##{m}", m] } + klass.map { |m| ["#{constant}.#{m}", m] }
    end
  end

  # The words the text doesn't name in code (SH-B70): an option as +x:+, a key as +x+, +:x+ or +x:+.
  #
  # @param markdown [String]
  # @param words [Array<String>]
  # @param form [Symbol] +:option+ or +:key+
  # @return [Array<String>]
  # @raise [ArgumentError] for any other form
  def unnamed_words(markdown, words, form:)
    raise ArgumentError, "unknown form #{form.inspect} (use :option or :key)" unless FORMS.include?(form)

    code = code_text(markdown)
    words.map(&:to_s).uniq.reject do |word|
      form == :option ? code.match?(/(?<![\w:])#{Regexp.escape(word)}:(?!:)/) : word?(code, word)
    end
  end

  # @api private
  def word?(code, word)
    code.match?(/(?<![\w@$])#{Regexp.escape(word)}(?!\w)/)
  end

  # @param text [String] one entry per line; +#+ lines and blanks are dropped
  # @return [Array<String>]
  def parse_allowlist(text)
    text.lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
  end

  # @param changelog [String]
  # @return [Boolean] whether the +[Unreleased]+ section has a non-blank line
  def unreleased_entry?(changelog)
    section = changelog[/^## \[Unreleased\][^\n]*\n(.*?)(?=^## \[|\z)/m, 1]
    !section.nil? && section.lines.any? { |line| !line.strip.empty? }
  end

  # A message when +lib/+ changed since +base+ and the CHANGELOG has no +[Unreleased]+ entry (SH-B75).
  #
  # @param root [String] the gem directory
  # @param base [String] a git revision
  # @return [String, nil]
  def changelog_failure(root, base:)
    _out, found = Open3.capture2e('git', 'rev-parse', '--verify', '--quiet', "#{base}^{commit}", chdir: root)
    unless found.success?
      warn "docs:check: #{base} doesn't resolve here, so the CHANGELOG check is skipped (set DOCS_CHECK_BASE)"
      return nil
    end

    changed, = Open3.capture2e('git', 'diff', '--name-only', '--relative', base, '--', 'lib', chdir: root)
    return nil if changed.strip.empty? || unreleased_entry?(File.read(File.join(root, 'CHANGELOG.md')))

    "lib/ changed since #{base} but CHANGELOG.md has no entry under [Unreleased]:\n#{changed}"
  end

  # One docs:check run for a gem (SH-B76): coverage of every target, the allowlist's staleness and the CHANGELOG.
  #
  # @param root [String] the gem directory (its +lib/+ and +support/docs_allowlist.txt+ are read)
  # @param api [Array<Array(String, Symbol)>]
  # @param targets [Hash{String => String}] label to Markdown text
  # @param words [Hash{Symbol => Array<String>}] +:option+ and +:key+ words every target must name
  # @param base [String, nil] the git revision for the CHANGELOG check; nil skips that check
  # @param lib [String] whose methods count (default +root/lib+)
  # @return [String, nil] the failure text, or nil when everything is named
  def check(root:, api:, targets:, words: {}, base: 'origin/main', lib: File.join(root, 'lib'))
    path = File.join(root, 'support/docs_allowlist.txt')
    allowlist = File.exist?(path) ? parse_allowlist(File.read(path)) : []
    missing = targets.to_h do |label, text|
      [label, unnamed_methods(text, api: api, lib: lib, allowlist: allowlist) +
        words.flat_map { |form, list| unnamed_words(text, list - allowlist, form: form) }]
    end
    stale = stale_allowlist(allowlist, api: api, lib: lib) - words.values.flatten
    changelog = base && changelog_failure(root, base: base)
    problems = [report(missing), stale_message(stale), changelog].compact
    problems.empty? ? nil : problems.join("\n")
  end

  # @api private
  def stale_message(stale)
    return nil if stale.empty?

    "support/docs_allowlist.txt has entries that match nothing (remove them):\n  #{stale.join("\n  ")}"
  end

  # The failure text for a docs:check run, or nil when every target names everything (SH-B76).
  #
  # @param missing [Hash{String => Array<String>}] target label to the names it lacks
  # @return [String, nil]
  def report(missing)
    gaps = missing.reject { |_, names| names.empty? }
    return nil if gaps.empty?

    lines = gaps.map { |target, names| "#{target} doesn't name these in code:\n  #{names.join("\n  ")}" }
    "#{lines.join("\n")}\nDocument each one (in a code span or an example), or add it to support/docs_allowlist.txt " \
      'under a comment that says why.'
  end
end
