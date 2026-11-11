# frozen_string_literal: true

RSpec.describe 'serialize mappings' do
  let(:klass) do
    Class.new(FieldStruct::Base) do
      required :first, :string
      optional :last, :string
    end
  end

  describe 'FS-B101' do
    it 'stores the mapping frozen, with String values, and returns the class' do
      expect(klass.serialize(:json, first: :firstName)).to equal(klass)
      mapping = klass.metadata.serialization(:json)
      expect(mapping).to eq(first: 'firstName')
      expect(mapping).to be_frozen
      expect(klass.metadata.serializations).to eq(json: { first: 'firstName' })
    end

    it 'accepts the format as a String, and String keys' do
      klass.serialize('json', 'first' => 'f')
      expect(klass.metadata.serialization(:json)).to eq(first: 'f')
      expect(klass.metadata.serialization('json')).to equal(klass.metadata.serialization(:json))
    end

    it 'refuses undeclared fields, naming every one' do
      expect { klass.serialize(:json, b: 'x', first: 'f', c: 'y') }.to raise_error(
        ArgumentError, 'serialize :json references undeclared field(s): :b, :c. Declare fields before calling serialize.'
      )
      expect(klass.metadata.serializations).to be_empty
    end

    it 'FS-B13: a reserved name can keep its external key through a mapped field' do
      k = Class.new(FieldStruct::Base) { optional :errors_field, :string }
      expect { k.serialize :json, errors_field: 'errors' }.not_to raise_error
      expect(k.new(errors_field: 'x').as_json).to eq(errors: 'x')
    end
  end

  describe 'FS-B102' do
    it 'keeps several formats; re-declaring a format replaces it entirely' do
      klass.serialize(:json, first: 'a', last: 'b')
      klass.serialize(:csv, first: 'F')
      klass.serialize(:json, last: 'z')
      expect(klass.metadata.serializations).to eq(json: { last: 'z' }, csv: { first: 'F' })
    end

    it 'gives one shared empty frozen Hash for undeclared formats and has no entry for them' do
      other = Class.new(FieldStruct::Base)
      expect(klass.metadata.serialization(:nope)).to eq({})
      expect(klass.metadata.serialization(:nope)).to be_frozen
      expect(klass.metadata.serialization(:nope)).to equal(other.metadata.serialization(:else))
      expect(klass.metadata.serializations).not_to have_key(:nope)
    end
  end

  describe 'FS-B103 inheritance' do
    it 'copies the parent mappings at creation; a child may replace, add a format, or map inherited fields' do
      klass.serialize(:json, first: 'a')
      child = Class.new(klass) { optional :height, :integer }
      expect(child.metadata.serialization(:json)).to eq(first: 'a')
      child.serialize(:json, first: 'b', height: 'years')
      child.serialize(:csv, last: 'L')
      expect(klass.metadata.serialization(:json)).to eq(first: 'a')
      expect(klass.metadata.serializations.keys).to eq([:json])
      expect(child.new(first: 'x', height: 3).as_json).to eq(b: 'x', last: nil, years: 3)
    end

    it 'snapshots: a mapping added to the parent later does not reach an existing child' do
      child = Class.new(klass)
      klass.serialize(:json, first: 'late')
      expect(child.metadata.serialization(:json)).to eq({})
    end

    it 'takes effect for from_json after the mapping changes' do
      klass.serialize(:json, first: 'a')
      expect(klass.from_json('{"a":"x"}').first).to eq('x')
      klass.serialize(:json, first: 'b')
      expect(klass.from_json('{"b":"x"}').first).to eq('x')
      expect(klass.from_json('{"a":"x"}').first).to be_nil
    end
  end

  describe 'FS-B159 (a) identity' do
    it 'returns the same frozen Hash until the format is redeclared' do
      klass.serialize(:json, first: 'a')
      first = klass.metadata.serialization(:json)
      expect(klass.metadata.serialization(:json)).to equal(first)
      klass.serialize(:json, first: 'a')
      expect(klass.metadata.serialization(:json)).not_to equal(first)
    end

    it 'a subclass shares its parent mapping object until it redeclares' do
      klass.serialize(:json, first: 'a')
      child = Class.new(klass)
      expect(child.metadata.serialization(:json)).to equal(klass.metadata.serialization(:json))
    end
  end

  describe 'Metadata#reverse_serialization' do
    it 'maps external to internal and is empty for undeclared formats' do
      klass.serialize(:json, first: 'a', last: 'b')
      expect(klass.metadata.reverse_serialization(:json)).to eq('a' => :first, 'b' => :last)
      expect(klass.metadata.reverse_serialization(:nope)).to eq({})
    end

    it 'stays correct after a direct write to serializations' do
      klass.serialize(:json, first: 'a')
      expect(klass.metadata.reverse_serialization(:json)).to eq('a' => :first)
      klass.metadata.serializations[:json] = { last: 'q' }.freeze
      expect(klass.metadata.reverse_serialization(:json)).to eq('q' => :last)
    end
  end
end
