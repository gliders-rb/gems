# frozen_string_literal: true

RSpec.describe FieldStruct::Base, '#with' do
  let(:klass) do
    Class.new(described_class) do
      required :name, :string
      optional :height, :integer
    end
  end

  let(:instance) { klass.new(name: 'Fern', height: 40) }

  it 'FS-B114: returns a changed copy and leaves the receiver alone' do
    copy = instance.with(height: '41')
    expect(copy).not_to equal(instance)
    expect(copy.height).to eq(41)
    expect(instance.height).to eq(40)
    expect(copy.class).to eq(klass)
  end

  it 'accepts String keys and returns an equal copy with no changes' do
    expect(instance.with('height' => 41).height).to eq(41)
    same = instance.with
    expect(same).to eq(instance)
    expect(same).not_to equal(instance)
  end

  it 'is subclass-safe' do
    sub = Class.new(klass)
    expect(sub.new(name: 'a').with(height: 1)).to be_a(sub)
  end

  it 'refuses positional arguments' do
    stub_const('Gardener', klass)
    expect { instance.with({ height: 1 }) }.to raise_error(
      ArgumentError, 'Gardener#with takes keyword arguments only, got 1 positional; pass a Hash as with(**hash)'
    )
    expect(instance.with(height: 2).height).to eq(2)
  end

  it 'rewrites errors for changed fields and carries over the others' do
    broken = klass.new(height: 'x')
    fixed = broken.with(name: 'Fern')
    expect(fixed.errors.to_h.keys).to eq([:height])
    expect(broken.errors.to_h.keys).to eq(%i[name height])
  end

  it 'works on immutable classes, and the copy is immutable again' do
    locked = Class.new(klass) { immutable! }
    original = locked.new(name: 'a')
    copy = original.with(name: 'b')
    expect(copy.name).to eq('b')
    expect { copy.name = 'c' }.to raise_error(FieldStruct::ImmutableError)
  end

  it 'freezes the copy when the receiver was frozen' do
    frozen = Class.new(klass) { frozen! }.new(name: 'a')
    expect(frozen.with(height: 1)).to be_frozen
    expect(instance.with(height: 1)).not_to be_frozen
    expect(instance.dup.freeze.with(height: 1)).to be_frozen
  end

  it 'does not re-run callable defaults' do
    calls = 0
    counted = Class.new(described_class) { field :n, :integer, default: -> { calls += 1 } }
    original = counted.new
    original.with(n: 5)
    original.with
    expect(calls).to eq(1)
  end

  it 'follows unknown_attributes and a :raise policy without returning a copy' do
    strict = Class.new(klass) do
      unknown_attributes :raise
      coercion_policy :raise
    end
    original = strict.new(name: 'a', height: 1)
    expect { original.with(zz: 1) }.to raise_error(FieldStruct::UnknownAttributeError)
    expect { original.with(height: 'x') }.to raise_error(FieldStruct::CoercionError)
    expect(original.height).to eq(1)
  end

  it 're-runs cross-field validators on the copy' do
    checked = Class.new(klass) { validate { |r| r.errors.add(:base, 'too old') if r.height.to_i > 50 } }
    expect(checked.new(name: 'a', height: 1).with(height: 60).errors[:base]).to eq(['too old'])
  end
end
