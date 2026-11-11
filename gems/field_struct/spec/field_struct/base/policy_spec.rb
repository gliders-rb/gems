# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'coercion policy and unknown attributes' do
  describe 'FS-B43 / FS-B44 class coercion_policy' do
    it 'defaults to :keep_raw and returns the symbol when set' do
      klass = Class.new(described_class)
      expect(klass.coercion_policy).to eq(:keep_raw)
      expect(klass.coercion_policy(:replace)).to eq(:replace)
      expect(klass.coercion_policy).to eq(:replace)
    end

    it 'inherits, and a child override never changes the parent' do
      parent = Class.new(described_class) { coercion_policy :replace }
      child = Class.new(parent)
      grandchild = Class.new(child) { coercion_policy :raise }
      expect([parent, child, grandchild].map(&:coercion_policy)).to eq(%i[replace replace raise])
      expect(described_class.coercion_policy).to eq(:keep_raw)
    end

    it 'rejects an unknown value at the macro call' do
      expect { Class.new(described_class) { coercion_policy :bad } }.to raise_error(
        ArgumentError, 'unknown coercion policy :bad (expected one of [:keep_raw, :replace, :raise])'
      )
    end

    it 'exposes the valid policy lists' do
      expect(described_class::VALID_COERCION_POLICIES).to eq(%i[keep_raw replace raise])
      expect(described_class::VALID_UNKNOWN_POLICIES).to eq(%i[ignore raise])
    end
  end

  describe 'FS-B43 effects' do
    it ':replace stores nil with the same error and skips presence' do
      klass = Class.new(described_class) do
        coercion_policy :replace
        required :n, :integer
      end
      instance = klass.new(n: 'x')
      expect(instance.n).to be_nil
      expect(instance.errors[:n]).to eq(['could not be coerced: Integer fields expect a base-10 integer, got a String that is not one'])
    end

    it ':raise raises CoercionError, keeps the old value and chains the cause' do
      stub_const('Counter', Class.new(described_class) do
        coercion_policy :raise
        optional :n, :integer
      end)
      counter = Counter.new(n: 1)
      error = begin
        counter.n = 'x'
      rescue FieldStruct::CoercionError => e
        e
      end
      expect(error.message).to eq(
        'could not coerce String input for n: Integer fields expect a base-10 integer, got a String that is not one'
      )
      expect(error.field_name).to eq(:n)
      expect(error.original).to be_a(ArgumentError)
      expect(error.cause).to equal(error.original)
      expect(counter.n).to eq(1)
    end

    it 'FS-B46: construction raises under :raise' do
      klass = Class.new(described_class) do
        coercion_policy :raise
        optional :n, :integer
      end
      expect { klass.new(n: 'x') }.to raise_error(FieldStruct::CoercionError)
    end

    it 'a field-level coercion_policy wins over the class policy, and redeclaring drops it' do
      klass = Class.new(described_class) do
        field :a, :integer, coercion_policy: :replace
        field :b, :integer
      end
      instance = klass.new(a: 'x', b: 'y')
      expect([instance.a, instance.b]).to eq([nil, 'y'])
      child = Class.new(klass) { field :a, :integer }
      expect(child.new(a: 'x').a).to eq('x')
      expect(klass.metadata[:a].coercion_policy).to eq(:replace)
    end

    it 'rejects a bad field-level policy at declaration' do
      expect { Class.new(described_class) { field :a, :integer, coercion_policy: :nope } }.to raise_error(
        ArgumentError, 'unknown coercion policy :nope (expected one of [:keep_raw, :replace, :raise])'
      )
    end
  end

  describe 'FS-B25 / FS-B26 unknown_attributes' do
    let(:strict) do
      Class.new(described_class) do
        unknown_attributes :raise
        field :a, :string, default: -> { raise 'default must not run' }
      end
    end

    it 'ignores unknown keys by default in new and assign_attributes' do
      klass = Class.new(described_class) { field :a, :string }
      expect(klass.unknown_attributes).to eq(:ignore)
      instance = klass.new(a: 'x', z: 1)
      expect(instance.assign_attributes(q: 1).a).to eq('x')
    end

    it 'raises before the defaults pass, listing every key in input order' do
      error = begin
        strict.new(z: 1, 'y' => 2, a: 'x')
      rescue FieldStruct::UnknownAttributeError => e
        e
      end
      expect(error.keys).to eq(%i[z y])
      expect(error.message).to eq("unknown attribute(s) for #{strict.inspect}: :z, :y")
    end

    it 'treats a String key of a field as known' do
      klass = Class.new(described_class) do
        unknown_attributes :raise
        field :a, :string
      end
      expect(klass.new('a' => 'x').a).to eq('x')
    end

    it 'raises from assign_attributes before assigning anything' do
      klass = Class.new(described_class) do
        unknown_attributes :raise
        field :a, :string
      end
      instance = klass.new(a: 'x')
      expect { instance.assign_attributes(a: 'y', z: 1) }.to raise_error(FieldStruct::UnknownAttributeError)
      expect(instance.a).to eq('x')
    end

    it 'inherits, and rejects a bad value' do
      expect(Class.new(strict).unknown_attributes).to eq(:raise)
      expect { Class.new(described_class) { unknown_attributes :bad } }.to raise_error(
        ArgumentError, 'unknown unknown_attributes policy :bad (expected one of [:ignore, :raise])'
      )
    end
  end
end
