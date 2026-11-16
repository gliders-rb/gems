# frozen_string_literal: true

require_relative '../../support/doc_tables'

# Generated reference tables come from the registry; a committed copy that differs fails here (run `rake docs:tables`).
RSpec.describe DocTables do
  it 'builds the option table from each type\'s option schema' do
    table = described_class.option_types
    expect(table.lines.first(2)).to eq(["| Option | Types |\n", "|---|---|\n"])
    expect(table).to include('| `base:` | `:integer` |', '| `zone:` | `:time`, `:datetime` |')
  end

  it 'replaces only the marked region' do
    text = "before\n<!-- generated: option-types -->\nold\n<!-- end generated -->\nafter\n"
    filled = described_class.fill(text, 'PAGE.md')
    expect(filled).to start_with("before\n<!-- generated: option-types -->\n| Option | Types |")
    expect(filled).to end_with("<!-- end generated -->\nafter\n")
  end

  it 'refuses a marker naming no table' do
    expect do
      described_class.fill("<!-- generated: tide-tables -->\n<!-- end generated -->\n", 'PAGE.md')
    end.to raise_error(ArgumentError, 'PAGE.md: no generated table named tide-tables')
  end

  it 'has every committed table up to date' do
    expect(described_class.stale).to eq([]), 'run `bundle exec rake docs:tables`'
  end

  it 'has a marked region in each target' do
    described_class::TARGETS.each do |path|
      expect(File.read(path)).to include('<!-- generated: option-types -->'), path
    end
  end
end
