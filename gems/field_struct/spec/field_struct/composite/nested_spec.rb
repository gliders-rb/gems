# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Nested do
  let(:bed) do
    stub_const('Bed', Class.new(FieldStruct::Base) do
      required :habitat, :string
      optional :plot_no, :string
    end)
  end

  let(:gardener) do
    bd = bed
    Class.new(FieldStruct::Base) do
      required :name, :string
      optional :border, bd
    end
  end

  describe 'FS-B2 declaration' do
    it 'accepts a Base subclass, or a registered name whose value is one' do
      expect(gardener.metadata[:border].type).to equal(described_class)
      expect(gardener.metadata[:border].type_instance).to be_a(described_class)
      expect(gardener.metadata[:border].type_instance.struct_class).to equal(bed)
      registry = FieldStruct.new_registry { register :bed, Bed }
      mod = Module.new.tap { |m| m.define_singleton_method(:field_types) { registry } }
      stub_const('Lib', mod)
      klass = stub_const('Lib::Holder', Class.new(FieldStruct::Base))
      bed
      klass.optional :border, :bed
      expect(klass.metadata[:border].type_instance.struct_class).to equal(bed)
    end

    it 'gives each field its own type instance (FS-B155)' do
      two = bed
      klass = Class.new(FieldStruct::Base) do
        optional :a, two
        optional :b, two
      end
      expect(klass.metadata[:a].type_instance).not_to equal(klass.metadata[:b].type_instance)
    end

    it 'FS-B81: accepts no native options, but pass-through ones' do
      bd = bed
      expect { Class.new(FieldStruct::Base) { optional :border, bd, strict: true } }.to raise_error(
        ArgumentError,
        'strict: option does not apply to Nested fields. It applies to: String, ImmutableString, Integer, UUID, URL, Email, Binary.'
      )
      klass = Class.new(FieldStruct::Base) { optional :border, bd, doc: 'x' }
      expect(klass.metadata[:border].options).to eq(doc: 'x')
    end
  end

  describe 'FS-B80 coercion' do
    it 'passes nil, an instance (same object) and a subclass instance; builds from a Hash' do
      klass = gardener
      instance = bed.new(habitat: 'Fen')
      expect(klass.new(name: 'a', border: instance).border).to equal(instance)
      child = Class.new(bed).new(habitat: 'x')
      expect(klass.new(name: 'a', border: child).border).to equal(child)
      expect(klass.new(name: 'a', border: nil).border).to be_nil
      built = klass.new(name: 'a', border: { habitat: 'Moor' }).border
      expect(built).to be_a(bed)
      expect(built.habitat).to eq('Moor')
    end

    it 'accepts a Hash with missing required keys (the nested struct is just invalid)' do
      expect(gardener.new(name: 'a', border: {}).border).to be_invalid
    end

    it 'refuses anything else through the parent\'s policy, naming classes only' do
      instance = gardener.new(name: 'a', border: 5)
      expect(instance.errors[:border]).to eq(['could not be coerced: expected Bed or Hash, got Integer'])
      expect(instance.border).to eq(5)
      replace = Class.new(gardener) { coercion_policy :replace }
      expect(replace.new(name: 'a', border: 5).border).to be_nil
    end

    it 'FS-B23: coerces a literal Hash default' do
      bd = bed
      klass = Class.new(FieldStruct::Base) { optional :border, bd, default: { habitat: 'Fen' } }
      expect(klass.new.border.habitat).to eq('Fen')
      expect(klass.new.border).not_to equal(klass.new.border)
    end

    it 'FS-B81 / FS-B164: ruby_type is the struct class; missing only for nil' do
      type = gardener.metadata[:border].type_instance
      expect(type.ruby_type).to equal(bed)
      expect([type.missing?(nil), type.missing?(bed.new)]).to eq([true, false])
    end

    it 'FS-B31: propagates inner errors unchanged and not through the parent\'s policy' do
      bd = Class.new(FieldStruct::Base) { unknown_attributes :raise }
      holder = Class.new(FieldStruct::Base) do
        coercion_policy :replace
        optional :inner, bd
      end
      expect { holder.new(inner: { z: 1 }) }.to raise_error(FieldStruct::UnknownAttributeError)
      boom = Class.new(FieldStruct::Base) { optional :n, :integer, default: -> { raise ArgumentError, 'inner' } }
      outer = Class.new(FieldStruct::Base) { optional :inner, boom }
      expect { outer.new(inner: {}) }.to raise_error(ArgumentError, 'inner')
    end

    it 'does not inherit the holder\'s unknown_attributes policy (FS-B26)' do
      strict = Class.new(gardener) { unknown_attributes :raise }
      expect { strict.new(name: 'a', border: { habitat: 'x', extra: 1 }) }.not_to raise_error
    end
  end

  describe 'FS-B39 validity at assignment' do
    it 'stamps "is invalid" for an invalid struct, nothing for a valid one' do
      expect(gardener.new(name: 'a', border: { habitat: 'x' })).to be_valid
      expect(gardener.new(name: 'a', border: {}).errors[:border]).to eq(['is invalid'])
    end

    it 'says "is required" for nil on a required nested field' do
      bd = bed
      klass = Class.new(FieldStruct::Base) { required :border, bd }
      expect(klass.new.errors[:border]).to eq(['is required'])
    end

    it 'checks arrays held by :value fields too' do
      broken = bed.new
      klass = Class.new(FieldStruct::Base) { optional :any, :value }
      expect(klass.new(any: [broken]).errors[:any]).to eq(['is invalid'])
      expect(klass.new(any: [1]).errors[:any]).to be_empty
    end

    it 'FS-B40: validity is not refreshed by in-place changes' do
      instance = gardener.new(name: 'a', border: { habitat: 'x' })
      instance.border.habitat = nil
      expect(instance).to be_valid
      instance.border = instance.border.dup
      expect(instance).to be_invalid
      instance.border.habitat = 'y'
      expect(instance).to be_invalid
    end
  end

  it 'prints a name for anonymous structs in the coercion message' do
    anon = Class.new(FieldStruct::Base)
    klass = Class.new(FieldStruct::Base) { optional :x, anon }
    expect(klass.new(x: 1).errors[:x]).to eq(['could not be coerced: expected AnonymousFieldStruct or Hash, got Integer'])
  end
end
