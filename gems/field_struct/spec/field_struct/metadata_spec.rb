# frozen_string_literal: true

RSpec.describe FieldStruct::Metadata do
  subject(:metadata) { described_class.new }

  def field(name, **options)
    FieldStruct::Field.new(name: name, type: FieldStruct::Types::String, **options)
  end

  it 'is Enumerable over Fields in declaration order' do
    a = field(:a)
    b = field(:b)
    metadata.add(a).add(b)
    expect(metadata).to be_a(Enumerable)
    expect(metadata.to_a).to eq([a, b])
    expect(metadata.map(&:name)).to eq(%i[a b])
    expect(metadata.each).to be_a(Enumerator)
  end

  describe '#add' do
    it 'returns self and replaces a same-named field in place' do
      first = field(:a)
      expect(metadata.add(first)).to equal(metadata)
      metadata.add(field(:b))
      replacement = field(:a, required: true)
      metadata.add(replacement)
      expect(metadata.names).to eq(%i[a b])
      expect(metadata[:a]).to equal(replacement)
    end
  end

  describe '#[]' do
    it 'accepts a String or Symbol and returns nil for unknown' do
      a = field(:a)
      metadata.add(a)
      expect(metadata[:a]).to equal(a)
      expect(metadata['a']).to equal(a)
      expect(metadata[:zz]).to be_nil
    end
  end

  describe '#names' do
    it 'FS-B159: returns a new Array each call' do
      metadata.add(field(:a))
      expect(metadata.names).to eq([:a])
      expect(metadata.names).not_to equal(metadata.names)
    end
  end

  describe 'FS-B159 (b) field identity' do
    it 'yields the same Field objects on every call' do
      a = field(:a)
      metadata.add(a)
      expect(metadata.first).to equal(a)
      expect(metadata.to_a.first).to equal(metadata.to_a.first)
    end
  end

  describe 'serializations' do
    it 'stores mappings frozen and starts empty' do
      expect(metadata.serializations).to eq({})
      metadata.add_serialization(:json, { a: 'A' })
      expect(metadata.serializations).to eq(json: { a: 'A' })
      expect(metadata.serialization(:json)).to be_frozen
    end

    it 'add_serialization returns self and keeps an already frozen mapping as is' do
      mapping = { a: 'A' }.freeze
      expect(metadata.add_serialization(:json, mapping)).to equal(metadata)
      expect(metadata.serialization(:json)).to equal(mapping)
    end

    it 'serialization takes a String or Symbol, and returns one shared empty frozen Hash for undeclared formats' do
      metadata.add_serialization(:json, { a: 'A' })
      expect(metadata.serialization('json')).to eq(a: 'A')
      empty = metadata.serialization(:csv)
      expect(empty).to eq({})
      expect(empty).to be_frozen
      expect(empty).to equal(described_class.new.serialization(:xml))
      expect(metadata.serializations).not_to have_key(:csv)
    end

    it 'reverse_serialization maps external to internal, and tracks later changes' do
      expect(metadata.reverse_serialization(:json)).to eq({})
      metadata.add_serialization(:json, { first: 'firstName' })
      expect(metadata.reverse_serialization(:json)).to eq('firstName' => :first)
      metadata.add_serialization(:json, { first: 'f', last: 'l' })
      expect(metadata.reverse_serialization(:json)).to eq('f' => :first, 'l' => :last)
      metadata.serializations[:json] = { last: 'L' }
      expect(metadata.reverse_serialization(:json)).to eq('L' => :last)
    end
  end

  describe '#merge' do
    it 'adds parent fields and serializations the receiver lacks; receiver wins' do
      parent = described_class.new
      parent_a = field(:a)
      parent.add(parent_a).add(field(:b))
      parent.add_serialization(:json, { a: 'A' })
      parent.add_serialization(:csv, { b: 'B' })

      own_b = field(:b, required: true)
      metadata.add(own_b)
      metadata.add_serialization(:csv, { b: 'mine' })

      expect(metadata.merge(parent)).to equal(metadata)
      expect(metadata.names).to eq(%i[b a])
      expect(metadata[:b]).to equal(own_b)
      expect(metadata[:a]).to equal(parent_a)
      expect(metadata.serialization(:csv)).to eq(b: 'mine')
      expect(metadata.serialization(:json)).to equal(parent.serialization(:json))
    end
  end

  describe '#inspect' do
    it 'shows empty' do
      expect(metadata.inspect).to eq('#<FieldStruct::Metadata empty>')
    end

    it 'lists field names and serializations' do
      metadata.add(field(:a)).add(field(:b))
      expect(metadata.inspect).to eq('#<FieldStruct::Metadata fields=[:a, :b]>')
      metadata.add_serialization(:json, { a: 'A' })
      expect(metadata.inspect).to eq('#<FieldStruct::Metadata fields=[:a, :b] serializations=[:json]>')
    end
  end
end
