# frozen_string_literal: true

require 'ripper'
require 'tmpdir'

# Every ```ruby block in the shipped docs must parse, marked for execution or not.
RSpec.describe 'docs ruby fences' do
  root = File.expand_path('../..', __dir__)
  files = %w[README.md USAGE.md AGENTS.md CHANGELOG.md docs/getting_started.md skills/actionable/SKILL.md]

  def ruby_fences(path)
    lines = File.readlines(path)
    fences = []
    index = 0
    while index < lines.size
      if lines[index].match?(/\A\s*```ruby\s*\z/)
        first = index + 1
        last = first
        last += 1 until last >= lines.size || lines[last].match?(/\A\s*```\s*\z/)
        fences << [first + 1, lines[first...last].join]
        index = last
      end
      index += 1
    end
    fences
  end

  it 'self-test: the scanner finds fences and the parser tells good from bad' do
    path = File.join(Dir.mktmpdir, 'x.md')
    File.write(path, "text\n```ruby\nx = 1\n```\n```sh\nls\n```\n```ruby\ndef broken(\n```\n")
    found = ruby_fences(path)
    expect(found.map(&:first)).to eq([3, 9])
    expect(Ripper.sexp(found[0].last)).not_to be_nil
    expect(Ripper.sexp(found[1].last)).to be_nil
  end

  files.each do |relative|
    path = File.join(root, relative)

    it "AC-I16: #{relative} has only ruby blocks that parse" do
      bad = ruby_fences(path).reject { |_line, source| Ripper.sexp(source) }
      expect(bad.map(&:first)).to be_empty, "#{relative}: ruby block(s) with a syntax error at line(s) #{bad.map(&:first).join(', ')}"
    end
  end
end
