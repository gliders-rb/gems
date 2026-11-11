# frozen_string_literal: true

RSpec.describe Actionable::Registry do
  subject(:store) { described_class.new }

  let(:first) { Class.new }
  let(:second) { Class.new }

  before do
    allow(first).to receive(:name).and_return('Alpha')
    allow(second).to receive(:name).and_return('Alpha')
  end

  it 'AC-B#registry: register returns self and lookups accept String or Symbol' do
    expect(store.register(first)).to equal(store)
    expect(store['Alpha']).to equal(first)
    expect(store[:Alpha]).to equal(first)
    expect(store['Nope']).to be_nil
  end

  it 'AC-B#registry: registering the same name replaces; anonymous classes are ignored' do
    store.register(first).register(second).register(Class.new)
    expect(store['Alpha']).to equal(second)
    expect(store.size).to eq(1)
  end

  it 'AC-B#registry: keys, values, size, empty? and each' do
    expect(store).to be_empty
    store.register(first)
    expect(store.keys).to eq(['Alpha'])
    expect(store.values).to eq([first])
    expect(store.each.to_a).to eq([['Alpha', first]])
    expect(store).not_to be_empty
  end
end
