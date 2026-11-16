# frozen_string_literal: true

RSpec.describe FieldStruct::JSONSchema, 'freeze: true' do
  before { described_class.clear_cache }

  let(:kiln) do
    struct do
      required :batch, :string, enum: %w[bisque glaze]
      optional :cone, :integer, default: 6
      optional :pieces, :array, of: :string
    end
  end

  def all_objects(value)
    case value
    when Hash then [value, *value.values.flat_map { |item| all_objects(item) }]
    when Array then [value, *value.flat_map { |item| all_objects(item) }]
    when String then [value]
    else []
    end
  end

  it 'JS-B44: returns the cached schema itself, the same object on every call' do
    first = described_class.generate(kiln, freeze: true)
    expect(described_class.generate(kiln, freeze: true)).to equal(first)
    expect(first).to eq(described_class.generate(kiln))
  end

  it 'JS-B44: is deep-frozen, so mutating it raises' do
    schema = described_class.generate(kiln, freeze: true)
    expect(all_objects(schema)).to all(be_frozen)
    expect { schema['properties']['batch']['enum'] << 'raku' }.to raise_error(FrozenError)
  end

  it 'JS-B40: a default call still returns a fresh mutable copy beside the frozen one' do
    frozen = described_class.generate(kiln, freeze: true)
    copy = described_class.generate(kiln)
    expect(copy).not_to be_frozen
    copy['properties']['batch']['enum'] << 'raku'
    expect(frozen['properties']['batch']['enum']).to eq(%w[bisque glaze])
  end

  it 'JS-B44: a schema that asked a hook is frozen but built for each call (JS-I7)' do
    asked = 0
    probe = Class.new(FieldStruct::Types::Base)
    probe.send(:define_method, :coerce) { |value, **| value }
    probe.send(:define_method, :ruby_type) { Rational }
    probe.send(:define_method, :json_schema) { (asked += 1) && { 'type' => 'string' } }
    klass = struct { required :ratio, probe }
    first = described_class.generate(klass, freeze: true)
    second = described_class.generate(klass, freeze: true)
    expect(asked).to eq(2)
    expect(first).to be_frozen
    expect(first).not_to equal(second)
  end

  it 'JS-B44: to_json_schema passes freeze: through' do
    klass = struct { required :glaze, :string }
    klass.include(FieldStruct::JSONSchema::Methods)
    expect(klass.to_json_schema(freeze: true)).to equal(described_class.generate(klass, freeze: true))
  end

  it 'JS-B44: refuses a freeze: that is not true or false' do
    expect { described_class.generate(kiln, freeze: nil) }
      .to raise_error(ArgumentError, 'FieldStruct::JSONSchema.generate expects freeze: to be true or false, got nil')
  end
end
