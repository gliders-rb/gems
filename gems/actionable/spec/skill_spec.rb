# frozen_string_literal: true

require 'json'

RSpec.describe 'the Claude Code skill and plugin' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:skill) { File.read(File.join(root, 'skills/actionable/SKILL.md')) }

  it 'AC-B#skill: has frontmatter with name, description and when_to_use' do
    front = skill[/\A---\n(.*?)\n---\n/m, 1]
    expect(front).to match(/^name: actionable$/)
    expect(front).to match(/^description: \S/)
    expect(front).to match(/^when_to_use: \S/)
  end

  it 'AC-B#skill: teaches the DSL, the verbs, the last-verb rule, codes, mistakes, composition, serialization, jobs and tests' do
    ['## Write an action', '## The verbs', 'must be the last thing', 'fails :deck_full', '## Common mistakes', 'Kernel',
     '## Compose', '## Serialize and inspect', '## Jobs', '## Test', 'actionable/rspec/coverage', 'actionable/rails',
     'USAGE.md'].each { |needle| expect(skill).to include(needle), needle }
    expect(skill).to match(/Result method/)
  end

  it 'AC-B#skill: the repo is a single-plugin marketplace' do
    plugin = JSON.parse(File.read(File.join(root, '.claude-plugin/plugin.json')))
    market = JSON.parse(File.read(File.join(root, '.claude-plugin/marketplace.json')))
    expect(plugin).to include('name' => 'actionable', 'skills' => './skills')
    expect(market['plugins'].size).to eq(1)
    expect(market['plugins'].first).to include('name' => 'actionable', 'source' => './')
  end
end
