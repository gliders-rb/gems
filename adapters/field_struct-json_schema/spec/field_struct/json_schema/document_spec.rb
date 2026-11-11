# frozen_string_literal: true

RSpec.describe FieldStruct::JSONSchema, 'document shape' do
  it 'JS-B1: writes $schema, title, type, properties, required in order for a named root' do
    stub_const('Hall::Card', struct { required :name, :string })
    schema = described_class.generate(Hall::Card)
    expect(schema).to eq(
      '$schema' => described_class::DRAFT, 'title' => 'Hall::Card', 'type' => 'object',
      'properties' => { 'name' => { 'type' => 'string' } }, 'required' => ['name']
    )
    expect(schema.keys).to eq(%w[$schema title type properties required])
  end

  it 'JS-B1: leaves out title for an anonymous root and required when empty' do
    schema = described_class.generate(struct { optional :a, :string })
    expect(schema.keys).to eq(%w[$schema type properties])
  end

  it 'JS-B1: includes inherited fields, parent first' do
    parent = struct { required :a, :string }
    child = Class.new(parent) { required :b, :integer }
    expect(described_class.generate(child)['properties'].keys).to eq(%w[a b])
  end

  it 'JS-B1/B16: adds additionalProperties false only under unknown_attributes :raise' do
    strict = struct do
      unknown_attributes :raise
      required :a, :string
    end
    expect(described_class.generate(strict).keys).to eq(%w[$schema type properties required additionalProperties])
    expect(described_class.generate(strict)['additionalProperties']).to be(false)
    expect(described_class.generate(struct { optional :a, :string })).not_to have_key('additionalProperties')
  end

  it 'JS-B2: uses serialization names; required excludes fields with a default (literal or callable)' do
    klass = struct do
      required :given_name, :string
      required :access, :string, default: 'public'
      required :stamp, :string, default: -> { 'now' }
      optional :age, :integer
      serialize :json, given_name: 'givenName'
    end
    schema = described_class.generate(klass)
    expect(schema['properties'].keys).to eq(%w[givenName access stamp age])
    expect(schema['required']).to eq(['givenName'])
  end

  describe 'JS-B4: annotations' do
    it 'orders description, default, x-sensitive before the core' do
      klass = struct { optional :access, :string, description: 'The access', default: 'public' }
      expect(property(klass, :access).keys).to eq(%w[description default type])
      expect(property(klass, :access)).to include('description' => 'The access', 'default' => 'public')
    end

    it 'leaves a sensitive default out, marks it, and keeps enum' do
      klass = struct { optional :token, :string, sensitive: true, default: 'abc', enum: %w[abc def] }
      expect(property(klass, :token)).to include('x-sensitive' => true)
      expect(property(klass, :token)).not_to have_key('default')
      expect(JSON.generate(property(klass, :token))).to include('"enum"')
    end
  end

  describe 'JS-B5: usable defaults' do
    def default_of(type, default, **opts)
      klass = struct { optional :f, type, default: default, **opts }
      property(klass, :f)['default']
    end

    def has_default?(type, default, **opts)
      klass = struct { optional :f, type, default: default, **opts }
      property(klass, :f).key?('default')
    end

    it 'keeps what to_json already writes' do
      expect(default_of(:string, 'x')).to eq('x')
      expect(default_of(:boolean, false)).to be(false)
      expect(default_of(:integer, 3)).to eq(3)
      expect(default_of(:float, 1)).to eql(1.0)
      expect(default_of(:float, 1.5)).to eql(1.5)
      expect(default_of(:symbol, :basic)).to eq('basic')
      expect(default_of(:value, { 'a' => [1, nil, 'x'] })).to eq('a' => [1, nil, 'x'])
    end

    it 'leaves out everything else' do
      expect(has_default?(:string, 1)).to be(false)
      expect(has_default?(:string, :sym)).to be(false)
      expect(has_default?(:float, Float::INFINITY)).to be(false)
      expect(has_default?(:float, Float::NAN)).to be(false)
      expect(has_default?(:integer, -> { 1 })).to be(false)
      expect(has_default?(:big_decimal, BigDecimal('1.5'))).to be(false)
      expect(has_default?(:date, Date.new(2026, 1, 1))).to be(false)
      expect(has_default?(:value, { a: 1 })).to be(false)
    end
  end

  describe 'JS-B6/B7: nullable' do
    it 'keeps required fields as they are and makes optional ones accept null' do
      klass = struct do
        required :a, :string
        optional :b, :string
        optional :c, :value
      end
      expect(property(klass, :a)).to eq('type' => 'string')
      expect(property(klass, :b)).to eq('type' => %w[string null])
      expect(property(klass, :c)).to eq({})
    end

    it 'JS-B7: appends nil to enum and adds the blank-string alternative for String-family enum/format/pattern' do
      klass = struct { optional :medium, :string, enum: %w[oil tempera] }
      alternatives = [{ 'type' => %w[string null], 'enum' => ['oil', 'tempera', nil] }, described_class::BLANK_STRING]
      expect(property(klass, :medium)).to eq('anyOf' => alternatives)
    end

    it 'JS-B7: uses the empty string for :binary and nothing for a type whose missing? is only nil' do
      binary = struct { optional :b, :binary, enum: ['x'] }
      expect(property(binary, :b)['anyOf'].last).to eq(described_class::EMPTY_STRING)

      custom = Class.new(FieldStruct::Types::String) do
        def missing?(value) = value.nil?
      end
      reg = struct { optional :c, custom, enum: ['x'] }
      expect(property(reg, :c)).to eq('type' => %w[string null], 'enum' => ['x', nil])
    end

    it 'JS-B20: required String-family fields get no blank alternative' do
      klass = struct { required :color, :string, enum: %w[red] }
      expect(property(klass, :color)).to eq('type' => 'string', 'enum' => ['red'])
    end
  end

  describe 'JS-B8..B10: scalars' do
    def schema_of(type, **opts)
      property(struct { required :f, type, **opts }, :f)
    end

    it 'maps the simple types' do
      expect(schema_of(:boolean)).to eq('type' => 'boolean')
      expect(schema_of(:integer)).to eq('type' => 'integer')
      expect(schema_of(:float)).to eq('type' => 'number')
      expect(schema_of(:value)).to eq({})
      expect(schema_of(:big_decimal)).to eq('type' => 'string', 'pattern' => described_class::DECIMAL_PATTERN)
      expect(schema_of(:big_decimal, in: 1..2)).to eq('type' => 'string', 'pattern' => described_class::DECIMAL_PATTERN)
      expect(schema_of(:symbol, enum: %i[a b])).to eq('type' => 'string', 'enum' => %w[a b])
      expect(schema_of(:symbol)).to eq('type' => 'string')
    end

    it 'maps temporal types, with format only for the iso8601 default' do
      expect(schema_of(:date)).to eq('type' => 'string', 'format' => 'date')
      expect(schema_of(:date, format: :iso8601)).to eq('type' => 'string', 'format' => 'date')
      expect(schema_of(:date, format: :us)).to eq('type' => 'string')
      expect(schema_of(:time)).to eq('type' => 'string', 'format' => 'date-time')
      expect(schema_of(:datetime)).to eq('type' => 'string', 'format' => 'date-time')
      expect(schema_of(:time, format: :db)).to eq('type' => 'string')
      expect(schema_of(:time, format: '%H')).to eq('type' => 'string')
      expect(schema_of(:time, format: :iso8601)).to eq('type' => 'string', 'format' => 'date-time')
    end

    it 'JS-B9: turns in: into enum or bounds' do
      expect(schema_of(:integer, in: 1..10)).to eq('type' => 'integer', 'minimum' => 1, 'maximum' => 10)
      expect(schema_of(:integer, in: 1...10)).to eq('type' => 'integer', 'minimum' => 1, 'exclusiveMaximum' => 10)
      expect(schema_of(:float, in: 0.0...1.0)).to eq('type' => 'number', 'minimum' => 0.0, 'exclusiveMaximum' => 1.0)
      expect(schema_of(:integer, in: 0..Float::INFINITY)).to eq('type' => 'integer', 'minimum' => 0)
      expect(schema_of(:integer, in: (..5))).to eq('type' => 'integer', 'maximum' => 5)
      expect(schema_of(:integer, in: [1, 2, 3])).to eq('type' => 'integer', 'enum' => [1, 2, 3])
      expect(schema_of(:float, in: BigDecimal('0.5')..BigDecimal('1.5'))).to eq('type' => 'number', 'minimum' => 0.5, 'maximum' => 1.5)
      expect(schema_of(:date, in: [Date.new(2026, 1, 1)])).to eq('type' => 'string', 'format' => 'date')
    end

    it 'JS-B10: uuid is a format, other regexps patterns (or x-ruby-pattern), enum as given' do
      expect(schema_of(:uuid)).to eq('type' => 'string', 'format' => 'uuid')
      expect(schema_of(:uuid, format: /\A[A-Z]{3}\z/)).to include('type' => 'string')
      expect(schema_of(:string, enum: %w[a b])).to eq('type' => 'string', 'enum' => %w[a b])
      expect(schema_of(:string)).to eq('type' => 'string')
      expect(schema_of(:binary)).to eq('type' => 'string')
      expect(schema_of(:immutable_string)).to eq('type' => 'string')
    end

    it 'JS-B10: annotates a Regexp pattern_for cannot translate with x-ruby-pattern' do
      allow(described_class).to receive(:pattern_for).and_return(nil)
      schema = schema_of(:string, format: /\Aab+\z/)
      expect(schema).to eq('type' => 'string', 'x-ruby-pattern' => '\Aab+\z')
    end

    it 'JS-B10: emits the translated pattern when pattern_for gives one' do
      allow(described_class).to receive(:pattern_for).with(/\Aab+\z/).and_return('^ab+$')
      expect(schema_of(:string, format: /\Aab+\z/)).to eq('type' => 'string', 'pattern' => '^ab+$')
    end
  end

  describe 'JS-I1: validates real to_json output' do
    it 'accepts valid instances and rejects mutated ones' do
      stub_const('Scalars', struct do
        required :name, :string
        optional :access, :string, enum: %w[public staff], default: 'public'
        optional :age, :integer, in: 0..150
        optional :ratio, :float, in: 0.0...1.0
        optional :when, :time
        optional :day, :date
        optional :price, :big_decimal
        optional :kind, :symbol, enum: %i[a b]
        optional :flag, :boolean
        optional :id, :uuid
        optional :extra, :value
      end)
      schema = described_class.generate(Scalars)
      full = Scalars.new(name: 'x', access: 'staff', age: 30, ratio: 0.5, when: Time.utc(2026, 1, 2, 3, 4, 5), day: Date.new(2026, 1, 2),
                         price: BigDecimal('12.50'), kind: :a, flag: true,
                         id: '123e4567-e89b-42d3-a456-426614174000', extra: { 'k' => [1] })
      expect(valid_json?(schema, full)).to be(true)
      expect(valid_json?(schema, Scalars.new(name: 'x'))).to be(true)
      data = Oj.load(full.to_json)
      [%w[access gold], ['age', 151], ['age', -1], ['ratio', 1.0], %w[when nope], %w[price abc], %w[kind z], %w[id zzz],
       ['name', nil]].each do |key, bad|
        expect(valid_value?(schema, data.merge(key => bad))).to be(false), "#{key}=#{bad.inspect} should be invalid"
      end
    end
  end
end
