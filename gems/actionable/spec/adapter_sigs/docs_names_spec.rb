# frozen_string_literal: true

# The names USAGE must mention include the adapters', so every adapter is loaded here.
require 'actionable/rails'
require 'actionable/job'
require 'actionable/rspec'
require 'actionable/rspec/coverage'
require_relative '../../support/docs_check'

RSpec.describe DocsCheck do
  it 'AC-B#docs: lists the public methods USAGE does not name, minus the allowlist' do
    missing = described_class.unnamed('', allowlist: [])
    expect(missing).to include('Actionable::Action#run', 'Actionable::BatchResult#partial?')
    named = described_class.unnamed('run partial?', allowlist: [])
    expect(named).not_to include('Actionable::Action#run', 'Actionable::BatchResult#partial?')
    allowed = described_class.unnamed('', allowlist: ['Actionable::Action#run'])
    expect(allowed).not_to include('Actionable::Action#run')
  end

  it 'AC-B#docs: a setter counts as named when its base name is' do
    expect(described_class.unnamed('verb_position_check', allowlist: [])).not_to include('Actionable#verb_position_check=')
  end

  it 'AC-B#docs: the shipped USAGE names every public API method outside the allowlist' do
    root = File.expand_path('../..', __dir__)
    allowlist = described_class.parse_allowlist(File.read(File.join(root, 'support/docs_allowlist.txt')))
    expect(described_class.unnamed(File.read(File.join(root, 'USAGE.md')), allowlist: allowlist)).to be_empty
  end
end
