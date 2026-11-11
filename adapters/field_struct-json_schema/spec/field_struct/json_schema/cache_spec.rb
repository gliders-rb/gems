# frozen_string_literal: true

RSpec.describe FieldStruct::JSONSchema, 'caching' do
  before { described_class.clear_cache }

  def builds
    count = 0
    allow(FieldStruct::JSONSchema::Builder).to receive(:new).and_wrap_original do |original, *args|
      count += 1
      original.call(*args)
    end
    yield
    count
  end

  it 'JS-B40: builds once per (class, serialization) and returns equal fresh copies' do
    klass = struct { required :a, :string }
    first = nil
    second = nil
    expect(builds do
      first = described_class.generate(klass)
      second = described_class.generate(klass)
    end).to eq(1)
    expect(first).to eq(second)
    expect(first).not_to be_frozen
    expect(first).not_to equal(second)
    expect(first['properties']['a']).not_to equal(second['properties']['a'])
  end

  it 'JS-B40: shares no mutable object between results, nested ones included' do
    klass = struct do
      required :a, :string, enum: %w[x y]
      optional :n, :integer, default: 3
      optional :list, :array, of: :string
    end
    objects = lambda do |value, seen = []|
      seen << value if value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(String)
      value.each_value { |item| objects.call(item, seen) } if value.is_a?(Hash)
      value.each { |item| objects.call(item, seen) } if value.is_a?(Array)
      seen
    end
    described_class.generate(klass)
    first = objects.call(described_class.generate(klass))
    second = objects.call(described_class.generate(klass))
    expect(first.size).to eq(second.size)
    expect(first.size).to be > 10
    expect(first.map(&:object_id) & second.map(&:object_id)).to be_empty
    expect(first.none?(&:frozen?)).to be(true)
  end

  it 'JS-B43: keeps one entry per serialization' do
    klass = struct do
      required :a, :string
      serialize :json, a: 'A'
    end
    expect(builds do
      described_class.generate(klass)
      described_class.generate(klass, serialization: :other)
      described_class.generate(klass)
      described_class.generate(klass, serialization: 'other')
    end).to eq(2)
  end

  it 'JS-B40/I5: mutating a result changes neither the class nor later results' do
    enum = %w[a b]
    default = { 'k' => ['v'] }
    override = { 'type' => 'array', 'items' => { 'enum' => [1] } }
    klass = struct do
      optional :status, :string, enum: enum
      optional :extra, :value, default: default
      required :o, :value, json_schema: override
    end
    schema = described_class.generate(klass)
    schema['properties']['status']['anyOf'].first['enum'] << 'x'
    schema['properties']['extra']['default']['k'] << 'mutated'
    schema['properties']['o']['items']['enum'] << 2
    schema['properties']['status']['anyOf'].first['enum'].first << 'zzz'
    expect(enum).to eq(%w[a b])
    expect(enum).not_to be_frozen
    expect(default).to eq('k' => ['v'])
    expect(override).to eq('type' => 'array', 'items' => { 'enum' => [1] })
    again = described_class.generate(klass)
    expect(again['properties']['status']['anyOf'].first['enum']).to eq(['a', 'b', nil])
    expect(again['properties']['extra']['default']).to eq('k' => ['v'])
  end

  it 'JS-I5: copies the very first result too (nothing is shared with the class options)' do
    override = { 'type' => 'integer' }
    klass = struct { required :o, :value, json_schema: override }
    schema = described_class.generate(klass)
    expect(schema['properties']['o']).not_to equal(override)
  end

  describe 'JS-B41: rebuilding' do
    it 'rebuilds when the root redeclares a field' do
      klass = struct { required :a, :string }
      described_class.generate(klass)
      klass.class_eval { required :a, :integer }
      expect(described_class.generate(klass)['properties']['a']).to eq('type' => 'integer')
    end

    it 'rebuilds when a $defs class changes' do
      stub_const('CInner', struct { required :x, :string })
      stub_const('COuter', struct { required :inner, CInner })
      described_class.generate(COuter)
      CInner.class_eval { required :y, :integer }
      expect(described_class.generate(COuter)['$defs']['CInner']['properties'].keys).to eq(%w[x y])
    end

    it 'rebuilds when an inlined anonymous class changes' do
      inner = struct { required :x, :string }
      outer = struct { required :inner, inner }
      described_class.generate(outer)
      inner.class_eval { required :y, :integer }
      expect(property(outer, :inner)['properties'].keys).to eq(%w[x y])
    end

    it 'rebuilds when the serialize mapping, unknown_attributes or the name change' do
      klass = struct { required :a, :string }
      described_class.generate(klass)
      klass.class_eval { serialize :json, a: 'A' }
      expect(described_class.generate(klass)['properties'].keys).to eq(['A'])
      klass.class_eval { unknown_attributes :raise }
      expect(described_class.generate(klass)['additionalProperties']).to be(false)
      expect(described_class.generate(klass)).not_to have_key('title')
      stub_const('Renamed', klass)
      expect(described_class.generate(klass)['title']).to eq('Renamed')
    end

    it 'does not memoize a document whose type hook was consulted, nested in an array or answering nil' do
      asked = 0
      probe = Class.new(FieldStruct::Types::Base)
      probe.send(:define_method, :coerce) { |value, **| value }
      probe.send(:define_method, :ruby_type) { Rational }
      probe.send(:define_method, :json_schema) { asked += 1 and nil }
      klass = struct { required :xs, :array, of: probe }
      2.times { described_class.generate(klass) }
      expect(asked).to eq(2)
    end
  end

  it 'JS-B42: does not notice an in-place option change' do
    enum = %w[a]
    klass = struct { required :s, :string, enum: enum }
    described_class.generate(klass)
    enum << 'b'
    expect(described_class.generate(klass)['properties']['s']['enum']).to eq(['a'])
    klass.class_eval { required :s, :string, enum: enum }
    expect(described_class.generate(klass)['properties']['s']['enum']).to eq(%w[a b])
  end

  it 'JS-B43: clear_cache empties it and returns nil' do
    klass = struct { required :a, :string }
    described_class.generate(klass)
    expect(described_class.clear_cache).to be_nil
    expect(builds { described_class.generate(klass) }).to eq(1)
  end

  it 'JS-B43: is safe to call from many threads' do
    klass = struct { required :a, :string }
    expected = described_class.generate(klass)
    results = Array.new(8) { Thread.new { Array.new(50) { described_class.generate(klass) } } }.flat_map(&:value)
    expect(results).to all(eq(expected))
  end
end
