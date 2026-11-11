# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'ripper'

# Dev-only: runs the Ruby examples in the docs. A line holding exactly <!-- doctest --> marks the ```ruby block
# after it as runnable; inside it, `expr # => value` is an assertion. Each block runs in its own Ruby process at top
# level, so examples can define real, named classes. Not packaged with the gem.
module Doctest
  Block = Struct.new(:path, :line, :source)

  MARKER = /\A\s*<!--\s*doctest\s*-->\s*\z/
  OPEN_FENCE = /\A\s*```ruby\s*\z/
  CLOSE_FENCE = /\A\s*```\s*\z/
  ARROW = /\A(?<code>.*?\S.*?)\s+#\s*=>\s?(?<value>.*)\z/
  BARE_ARROW = /\A\s*#\s*=>/

  module_function

  # The marked blocks of a file.
  #
  # @param path [String]
  # @return [Array<Block>]
  # @raise [ArgumentError] when a marker has no ruby block after it, or the file has no marked block
  def blocks(path)
    lines = File.readlines(path)
    found = []
    lines.each_with_index do |text, index|
      next unless text.match?(MARKER)

      found << read_block(path, lines, index)
    end
    raise ArgumentError, "#{path}: no doctest blocks (mark a ```ruby block with <!-- doctest -->)" if found.empty?

    found
  end

  # Runs a block in a fresh Ruby process.
  #
  # @param block [Block]
  # @param requires [Array<String>] features to require first
  # @param includes [Array<String>] load paths
  # @return [Array(Boolean, String)] whether it passed, and its stderr
  def run(block, requires: [], includes: [])
    command = [RbConfig.ruby, *includes.flat_map { |dir| ['-I', dir] }, '-']
    _out, err, status = Open3.capture3(*command, stdin_data: assertions(block, requires: requires))
    [status.success?, err]
  end

  # The script a block is run as: one line per source line, so error line numbers match the document.
  #
  # @param block [Block]
  # @param requires [Array<String>]
  # @return [String]
  def assertions(block, requires: [])
    lines = block.source.lines.map(&:chomp)
    out = []
    index = 0
    while index < lines.size
      line, consumed = rewrite(block, lines, index)
      out << line
      out.concat([''] * (consumed - 1))
      index += consumed
    end
    prelude = requires.map { |feature| "require #{feature.inspect}; " }.join + DEFINITION
    out[0] = "#{prelude}#{out[0]}"
    "#{out.join("\n")}\n"
  end

  DEFINITION = 'def __doctest_check(actual, expected, where); return if actual == expected; ' \
               "warn \"\#{where}: documented \#{expected.inspect}, got \#{actual.inspect}\"; exit 1; end; "

  def read_block(path, lines, marker_index)
    index = marker_index + 1
    index += 1 while index < lines.size && lines[index].strip.empty?
    unless index < lines.size && lines[index].match?(OPEN_FENCE)
      raise ArgumentError, "#{path}:#{marker_index + 1}: a doctest marker needs a ```ruby block right after it"
    end

    first = index + 1
    last = first
    last += 1 until last >= lines.size || lines[last].match?(CLOSE_FENCE)
    Block.new(path, first + 1, lines[first...last].join)
  end

  def rewrite(block, lines, index)
    line = lines[index]
    where = "#{File.basename(block.path)}:#{block.line + index}"
    raise ArgumentError, "#{where}: a # => needs the expression on the line right before it" if line.match?(BARE_ARROW)

    match = ARROW.match(line)
    return [line, 1] unless match

    value, consumed = documented_value(match[:value], lines, index, where)
    return [match[:code], consumed] if value.start_with?('#<')

    ["__doctest_check((#{match[:code]}), (#{value}), #{where.inspect})", consumed]
  end

  def documented_value(first, lines, index, where)
    value = first.strip
    raise ArgumentError, "#{where}: a # => with no value after it" if value.empty?

    consumed = 1
    until value.start_with?('#<') || Ripper.sexp(value)
      following = lines[index + consumed]
      unless following&.match?(/\A\s*#/) && !following.match?(BARE_ARROW)
        raise ArgumentError, "#{where}: the documented value isn't Ruby, so it can't be checked: #{value}"
      end

      value = "#{value} #{following.sub(/\A\s*#\s?/, '').strip}"
      consumed += 1
    end
    [value, consumed]
  end
  private_class_method :read_block, :rewrite, :documented_value
end
