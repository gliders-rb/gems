# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'ripper'
require 'tempfile'

# Runs the Ruby examples in Markdown: every gem's README, USAGE and guides, and the site's pages.
#
# A fence whose language is +ruby+ and whose meta has the word +run+ is runnable. All runnable blocks of a file run in
# order in one fresh Ruby process at top level, so they share classes, constants and locals. A line
# <tt>expr # => value</tt>, or a <tt># => value</tt> alone under a one-line expression, is an equality assertion.
# Dev-only: a private gem in the monorepo, never published.
module Doctest
  # A runnable block: the file, the line of its first source line, and the source.
  Block = Struct.new(:path, :line, :source)
  # What a file's run gave: whether it passed, its stderr, and how many blocks ran.
  Run = Struct.new(:ok, :stderr, :blocks)

  FENCE = /\A(\s*)(`{3,}|~{3,})\s*(\w+)?\s*(.*)\z/
  ARROW = /\A(?<code>.*?\S.*?)\s+#\s*=>\s?(?<value>.*)\z/
  BARE_ARROW = /\A\s*#\s*=>\s?(?<value>.*)\z/
  CONTINUATION = /\A\s*#/

  # Defined in the run before any block: collects every mismatch, so a file reports all of them.
  CHECK = <<~'RUBY'
    $__doctest_failures = []
    def __doctest_check(actual, expected, where)
      return actual if actual == expected

      warn "#{where}: documented #{expected.inspect}, got #{actual.inspect}"
      $__doctest_failures << where
      actual
    end
  RUBY

  module_function

  # The runnable blocks of a file, in order.
  #
  # @param path [String]
  # @return [Array<Block>] empty when the file has none
  def blocks(path)
    lines = File.readlines(path, chomp: true)
    found = []
    index = 0
    while index < lines.size
      match = lines[index].match(FENCE)
      index = match ? read_fence(path, lines, index, match, found) : index + 1
    end
    found
  end

  # The program a file runs as: the requires, the check, then each block evaluated at top level with its own
  # file and line, so a backtrace points into the document.
  #
  # @param blocks [Array<Block>]
  # @param requires [Array<String>] features to require first
  # @return [String]
  # @raise [ArgumentError] for a +# =>+ that would check nothing
  def script(blocks, requires: [])
    out = requires.map { |feature| "require #{feature.inspect}" }
    out << CHECK
    blocks.each do |block|
      out << "eval(#{rewrite_block(block).inspect}, TOPLEVEL_BINDING, #{block.path.inspect}, #{block.line})"
    end
    out << 'exit($__doctest_failures.empty? ? 0 : 1)'
    "#{out.join("\n")}\n"
  end

  # Runs a file's blocks in one fresh process.
  #
  # @param path [String]
  # @param requires [Array<String>] features to require first
  # @param includes [Array<String>] load paths (+-I+), used without +gemfile:+
  # @param gemfile [String, nil] run under +bundle exec+ with this Gemfile instead of the caller's bundle
  # @return [Run]
  # @raise [ArgumentError] for a +# =>+ that would check nothing
  def run_file(path, requires: [], includes: [], gemfile: nil)
    found = blocks(path)
    return Run.new(true, '', 0) if found.empty?

    Tempfile.create(['doctest', '.rb']) do |file|
      file.write(script(found, requires: requires))
      file.flush
      _out, err, status = Open3.capture3(*command(gemfile, includes, file.path))
      Run.new(status.success?, err, found.size)
    end
  end

  def command(gemfile, includes, path)
    loads = includes.flat_map { |dir| ['-I', dir] }
    return [RbConfig.ruby, *loads, path] unless gemfile

    [{ 'BUNDLE_GEMFILE' => gemfile }, 'bundle', 'exec', 'ruby', *loads, path]
  end

  def read_fence(path, lines, index, match, found)
    indent, fence, lang, meta = match.captures
    first = index + 1
    last = first
    last += 1 while last < lines.size && !lines[last].strip.start_with?(fence)
    if lang == 'ruby' && meta.gsub(/title="[^"]*"/, '').match?(/\brun\b/)
      body = lines[first...last].map { |line| line.sub(/\A {0,#{indent.size}}/, '') }
      found << Block.new(path, first + 1, "#{body.join("\n")}\n")
    end
    last + 1
  end

  # One output line per source line, so line numbers in errors match the document.
  def rewrite_block(block)
    lines = block.source.lines.map(&:chomp)
    out = []
    index = 0
    while index < lines.size
      consumed = rewrite(block, lines, index, out)
      index += consumed
    end
    "#{out.join("\n")}\n"
  end

  def rewrite(block, lines, index, out)
    line = lines[index]
    where = "#{block.path}:#{block.line + index}"
    if (bare = BARE_ARROW.match(line))
      above = "#{block.path}:#{block.line + index - 1}"
      return assert_line_above(lines, index, bare[:value], out, [where, above])
    end

    match = ARROW.match(line)
    unless match
      out << line
      return 1
    end

    value, consumed = documented_value(match[:value], lines, index, where)
    out << (value.start_with?('#<') ? match[:code] : check_call(match[:code], value, where))
    out.concat([''] * (consumed - 1))
    consumed
  end

  # A +# =>+ alone on its line asserts the one-line expression right above it.
  def assert_line_above(lines, index, first, out, (where, above_where))
    above = index.positive? ? lines[index - 1] : ''
    raise ArgumentError, "#{where}: a # => needs the expression on the line right before it" unless expression?(above)

    value, consumed = documented_value(first, lines, index, where)
    out[-1] = check_call(above, value, above_where) unless value.start_with?('#<')
    out.concat([''] * consumed)
    consumed
  end

  def expression?(line)
    stripped = line.strip
    return false if stripped.empty? || stripped.start_with?('#') || ARROW.match?(line)

    Ripper.sexp(stripped) ? true : false
  end

  def check_call(code, value, where)
    lead = code[/\A\s*/]
    "#{lead}__doctest_check((#{code.strip}), (#{value}), #{where.inspect})"
  end

  def documented_value(first, lines, index, where)
    value = first.strip
    raise ArgumentError, "#{where}: a # => with no value after it" if value.empty?

    consumed = 1
    until value.start_with?('#<') || Ripper.sexp(value)
      following = lines[index + consumed]
      unless following&.match?(CONTINUATION) && !following.match?(BARE_ARROW)
        raise ArgumentError, "#{where}: the documented value isn't Ruby, so it can't be checked: #{value}"
      end

      value = "#{value} #{following.sub(/\A\s*#\s?/, '').strip}"
      consumed += 1
    end
    [value, consumed]
  end
  private_class_method :command, :read_fence, :rewrite_block, :rewrite, :assert_line_above, :expression?,
                       :check_call, :documented_value
end
