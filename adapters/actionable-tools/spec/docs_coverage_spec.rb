# frozen_string_literal: true

RSpec.describe 'doc coverage' do
  it 'SH-B76: the README and the site page name every public method' do
    skip 'the ActiveSupport lane checks behaviour; the pages are the same text' if ENV['ACTIVE_SUPPORT_LANE']

    require 'doccheck'
    require_relative '../support/docs_coverage'
    failure = DocCheck.check(root: DocsCoverage::ROOT, api: DocsCoverage.api, targets: DocsCoverage.targets,
                             words: DocsCoverage.words, base: nil)
    expect(failure).to be_nil, failure
  end
end
