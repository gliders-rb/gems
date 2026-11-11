# frozen_string_literal: true

RSpec.describe Actionable::History do
  subject(:history) { described_class.new }

  let(:started) { Time.utc(2026, 1, 2, 3, 4, 5, 123_456) }

  def step(name: :one, duration: 0.5, code: nil, nested: nil)
    Actionable::History::Step.new(section: :main, name: name, started_at: started, duration: duration, code: code,
                                  nested: nested)
  end

  it 'AC-B#historyapi: << returns self; empty?, steps and took' do
    expect(history).to be_empty
    expect(history << step).to equal(history)
    history << step(duration: 1.5)
    expect(history.steps.size).to eq(2)
    expect(history.took).to eq(2.0)
    expect(history).not_to be_empty
  end

  it 'AC-B#historyapi: as_json has the documented keys, ISO started_at and class names for action steps' do
    stub_const('Child', Class.new)
    inner = described_class.new << step(name: :inner)
    history << step(name: Child, code: :success, nested: inner)
    json = history.as_json.first
    expect(json.keys).to eq(%i[section name started_at duration code history])
    expect(json).to include(section: :main, name: 'Child', started_at: '2026-01-02T03:04:05.123456Z', code: :success)
    expect(json[:history]).to eq(inner.as_json)
    expect(history.as_json.first[:history].first[:history]).to be_nil
  end

  it 'AC-B#historyapi: to_json goes through Oj compat and loads back with string keys' do
    history << step(code: :success)
    loaded = Oj.load(history.to_json)
    expect(loaded.first).to include('section' => 'main', 'name' => 'one', 'code' => 'success', 'history' => nil)
  end
end
