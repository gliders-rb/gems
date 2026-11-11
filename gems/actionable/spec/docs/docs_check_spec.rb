# frozen_string_literal: true

require_relative '../../support/docs_check'

RSpec.describe DocsCheck do
  it 'AC-B#docs: reads an allowlist, ignoring comments and blanks' do
    expect(described_class.parse_allowlist("# why\n\nfoo\n  bar  \n")).to eq(%w[foo bar])
  end

  it 'AC-B#docs: finds an [Unreleased] entry only when the section has content' do
    empty = "# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n- old\n"
    filled = "# Changelog\n\n## [Unreleased]\n\n- Added x\n\n## [1.0.0]\n- old\n"
    expect(described_class.unreleased_entry?(empty)).to be(false)
    expect(described_class.unreleased_entry?(filled)).to be(true)
    expect(described_class.unreleased_entry?("## [1.0.0]\n- old\n")).to be(false)
  end
end
