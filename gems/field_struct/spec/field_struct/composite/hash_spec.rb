# frozen_string_literal: true

module TideTable
  class Reading < FieldStruct::Base
    required :metres, :float
    optional :taken_at, :time
  end
end

RSpec.describe FieldStruct::Types::Hash do
  def harbour(&block)
    Class.new(FieldStruct::Base, &block)
  end

  describe 'FS-B79a: declaring' do
    it 'needs of:' do
      expect { harbour { optional :depths, :hash } }
        .to raise_error(ArgumentError, 'hash field requires an `of:` option naming the value type')
    end

    it 'checks element: against the value type, with a hash prefix' do
      expect { harbour { optional :depths, :hash, of: :integer, element: { round: 2 } } }
        .to raise_error(ArgumentError, /\Ain element: of hash field :depths, round: is not an Integer option/)
    end

    it 'is refused as a union member' do
      expect { harbour { optional :mark, :union, of: %i[string hash] } }.to raise_error(ArgumentError, /cannot include :hash/)
    end
  end

  describe 'FS-B79b: coercion' do
    let(:klass) { harbour { optional :depths, :hash, of: :integer } }

    it 'gives a new Hash with String keys and coerced values, nil values kept' do
      input = { 'north' => '4', south: 7, east: nil }
      record = klass.new(depths: input)
      expect(record.depths).to eq('north' => 4, 'south' => 7, 'east' => nil)
      expect(record.depths).not_to equal(input)
    end

    it 'lets the later of a Symbol and a String spelling win' do
      expect(klass.new(depths: { 'pier' => 1, pier: 2 }).depths).to eq('pier' => 2)
    end

    it 'refuses a non-Hash and other key classes, naming only the class' do
      record = klass.new(depths: [1])
      expect(record.errors[:depths].first).to include('expected Hash, got Array')
      record = klass.new(depths: { 3 => 1 })
      expect(record.errors[:depths].first).to include('hash keys must be Strings or Symbols, got Integer')
      expect(record.errors[:depths].first).not_to include('3')
    end

    it 'names a count of refused values, never a key' do
      one = klass.new(depths: { 'jetty' => 'deep', 'quay' => 2 }).errors[:depths].first
      many = klass.new(depths: { 'jetty' => 'deep', 'quay' => 'x', 'slip' => 'y' }).errors[:depths].first
      expect(one).to start_with('could not be coerced: value of 1 entry: ')
      expect(many).to start_with('could not be coerced: values of 3 entries (first shown): ')
      expect(one + many).not_to include('jetty')
    end
  end

  it 'FS-B79c: is missing when nil or empty' do
    klass = harbour { required :depths, :hash, of: :integer }
    expect(klass.new(depths: {}).errors[:depths]).to eq(['is required'])
    expect(klass.new(depths: { 'a' => 1 })).to be_valid
  end

  it 'FS-B79d: checks element: restrictions on each value and names a count' do
    klass = harbour { optional :depths, :hash, of: :integer, element: { in: 0..20 } }
    expect(klass.new(depths: { 'a' => 30 }).errors[:depths]).to eq(['1 entry is invalid'])
    expect(klass.new(depths: { 'a' => 30, 'b' => -1, 'c' => 5 }).errors[:depths]).to eq(['2 entries are invalid'])
  end

  describe 'FS-B79e: struct values' do
    let(:klass) { harbour { optional :gauges, :hash, of: TideTable::Reading } }

    it 'builds each value, and an invalid one makes the field invalid with a keyed path' do
      record = klass.new(gauges: { 'harbour mouth' => { metres: '2.5' }, 'pier' => {} })
      expect(record.gauges['harbour mouth']).to be_a(TideTable::Reading)
      expect(record.errors[:gauges]).to eq(['is invalid'])
      expect(record.errors.paths).to eq('gauges{"pier"}.metres' => ['is required'])
    end

    it 'round-trips through JSON with String keys' do
      record = klass.new(gauges: { 'pier' => { metres: 1.5 } })
      expect(record.as_json).to eq(gauges: { 'pier' => { metres: 1.5, taken_at: nil } })
      expect(klass.from_json(record.to_json)).to eq(record)
    end
  end

  it 'FS-B79f: ruby_type is Hash and RBS names String keys' do
    klass = harbour do
      optional :depths, :hash, of: :integer
      optional :gauges, :hash, of: TideTable::Reading
    end
    expect(described_class.new.ruby_type).to eq(Hash)
    expect(FieldStruct::RBS.type_for(klass.metadata[:depths])).to eq('::Hash[::String, ::Integer?]?')
    expect(FieldStruct::RBS.type_for(klass.metadata[:gauges])).to eq('::Hash[::String, ::TideTable::Reading]?')
  end

  it 'FS-B146a: Introspection gives a MapNode with the value node' do
    klass = harbour { optional :depths, :hash, of: :integer, element: { in: 0..9 } }
    node = FieldStruct::Introspection.properties(klass).first.node
    expect(node).to be_a(FieldStruct::Introspection::MapNode)
    expect(node).not_to be_a(FieldStruct::Introspection::ArrayNode)
    expect(node.element).to be_a(FieldStruct::Introspection::ScalarNode)
    expect(node.element.options).to eq(in: 0..9)
  end
end
