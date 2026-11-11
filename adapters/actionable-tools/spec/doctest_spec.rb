# frozen_string_literal: true

require 'tmpdir'
require_relative '../support/doctest'

RSpec.describe Doctest do
  def doc(text)
    dir = Dir.mktmpdir
    path = File.join(dir, 'DOC.md')
    File.write(path, text)
    path
  end

  def block(source, line: 1)
    Doctest::Block.new('/x/DOC.md', line, source)
  end

  describe '.blocks' do
    it 'finds ruby blocks right after a marker, blank lines allowed, with the first source line number' do
      path = doc("intro\n\n<!-- doctest -->\n\n```ruby\nx = 1\ny = 2\n```\n\n```ruby\nnot_run\n```\n  " \
                 "<!--doctest-->\n```ruby\nz = 3\n```\n")
      found = described_class.blocks(path)
      expect(found.map(&:source)).to eq(["x = 1\ny = 2\n", "z = 3\n"])
      expect(found.map(&:line)).to eq([6, 15])
    end

    it 'refuses a marker with no ruby block' do
      path = doc("<!-- doctest -->\n\n```sh\nls\n```\n")
      expect do
        described_class.blocks(path)
      end.to raise_error(ArgumentError, "#{path}:1: a doctest marker needs a ```ruby block right after it")
    end

    it 'refuses a file with no marked block' do
      path = doc("```ruby\nx = 1\n```\n")
      expect do
        described_class.blocks(path)
      end.to raise_error(ArgumentError, "#{path}: no doctest blocks (mark a ```ruby block with <!-- doctest -->)")
    end
  end

  describe '.assertions' do
    it 'turns expr # => value into an equality check and keeps one line per source line' do
      script = described_class.assertions(block("a = 1 + 1 # => 2\nputs a\n"))
      expect(script.lines.size).to eq(2)
      expect(script).to include('__doctest_check((a = 1 + 1), (2), "DOC.md:1")')
    end

    it 'joins a value that wraps over comment lines' do
      script = described_class.assertions(block("[1, 2,\n 3].sum # => 6\nlist # => [1,\n#   2]\n"))
      expect(script).to include('(list)').and include('([1, 2])')
    end

    it 'copies whole-line comments and leaves a plain comment after a complete value' do
      script = described_class.assertions(block("# note\nx = 1 # => 1\n# trailing remark\n"))
      expect(script).to include("# note\n").and include('# trailing remark')
    end

    it 'shows but does not check an inspect string' do
      script = described_class.assertions(block("obj # => #<Thing a: 1>\n"))
      expect(script).not_to include('__doctest_check((obj)')
      expect(script).to include('obj')
    end

    it 'refuses arrows that would check nothing' do
      expect do
        described_class.assertions(block("# => 3\n"))
      end.to raise_error(ArgumentError,
                         'DOC.md:1: a # => needs the expression on the line right before it')
      expect { described_class.assertions(block("x # =>\n")) }.to raise_error(ArgumentError, 'DOC.md:1: a # => with no value after it')
      expect do
        described_class.assertions(block("x # => [1,\n"))
      end.to raise_error(ArgumentError,
                         "DOC.md:1: the documented value isn't Ruby, so it can't be checked: [1,")
    end
  end

  describe '.run' do
    it 'passes a true document' do
      passed, err = described_class.run(block("class Thing; def n = 3; end\nThing.new.n # => 3\n"))
      expect(passed).to be(true), err
    end

    it 'fails a false one, naming file:line and both values' do
      passed, err = described_class.run(block("x = 1\nx + 1 # => 3\n", line: 10))
      expect(passed).to be(false)
      expect(err).to include('DOC.md:11: documented 3, got 2')
    end

    it 'requires features first, in a separate process' do
      passed, err = described_class.run(block("Set.new([1]).size # => 1\n"), requires: ['set'])
      expect(passed).to be(true), err
    end
  end
end
