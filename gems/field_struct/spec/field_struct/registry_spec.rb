# frozen_string_literal: true

RSpec.describe FieldStruct::Registry do
  let(:type_a) { Class.new(FieldStruct::Types::Base) }
  let(:type_b) { Class.new(FieldStruct::Types::Base) }

  it 'FS-B123: starts with no parent and no types' do
    registry = described_class.new
    expect(registry.parent).to be_nil
    expect(registry.type_classes).to eq([])
    expect(registry.key?(:x)).to be(false)
  end

  it 'FS-B123: lookup of an unknown name raises KeyError naming it via inspect' do
    expect { described_class.new.lookup(:nope) }
      .to raise_error(KeyError, 'no FieldStruct type registered for :nope')
  end

  it 'FS-B123: register makes lookup work for String or Symbol, and key? true' do
    registry = described_class.new.register(:x, type_a)
    expect(registry.lookup('x')).to equal(type_a)
    expect(registry.lookup(:x)).to equal(type_a)
    expect(registry.key?('x')).to be(true)
  end

  it 'FS-B123: register accepts a String name and returns self' do
    registry = described_class.new
    expect(registry.register('y', type_a)).to equal(registry)
    expect(registry.lookup(:y)).to equal(type_a)
  end

  it 'FS-B123: a later register overwrites' do
    registry = described_class.new.register(:x, type_a).register(:x, type_b)
    expect(registry.lookup(:x)).to equal(type_b)
  end

  it 'FS-B123: a Symbol target is an alias resolved immediately' do
    registry = described_class.new.register(:x, type_a).register(:y, :x)
    registry.register(:x, type_b)
    expect(registry.lookup(:y)).to equal(type_a)
  end

  it 'FS-B123: an alias to an unknown target raises KeyError at registration' do
    expect { described_class.new.register(:y, :missing) }.to raise_error(KeyError)
  end

  it 'FS-B123: an alias resolves through the parent chain' do
    parent = described_class.new.register(:x, type_a)
    child = described_class.new(parent).register(:y, :x)
    expect(child.lookup(:y)).to equal(type_a)
  end

  it 'FS-B123: children see parent entries and shadow them' do
    parent = described_class.new.register(:x, type_a)
    child = described_class.new(parent)
    expect(child.lookup(:x)).to equal(type_a)
    expect(child.key?(:x)).to be(true)
    child.register(:x, type_b)
    expect(child.lookup(:x)).to equal(type_b)
    expect(parent.lookup(:x)).to equal(type_a)
    expect(child.parent).to equal(parent)
  end

  it 'FS-B123: type_classes lists distinct classes, own first then parent' do
    parent = described_class.new.register(:p, type_a).register(:q, :p)
    child = described_class.new(parent).register(:c, type_b).register(:d, type_a)
    expect(child.type_classes).to eq([type_b, type_a])
  end

  describe '#inspect' do
    it 'lists registered names' do
      registry = described_class.new.register(:a, type_a).register(:b, type_b)
      expect(registry.inspect).to eq('#<FieldStruct::Registry types=[:a, :b]>')
    end

    it 'appends parent when there is one' do
      child = described_class.new(described_class.new).register(:a, type_a)
      expect(child.inspect).to eq('#<FieldStruct::Registry types=[:a] parent>')
    end
  end
end
