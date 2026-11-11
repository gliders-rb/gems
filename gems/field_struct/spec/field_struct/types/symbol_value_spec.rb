# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Symbol do
  subject(:type) { described_class.new }

  it 'FS-B164: ruby_type is Symbol, enum: is declared' do
    expect(type.ruby_type).to eq(Symbol)
    expect(described_class.option_schema.keys).to eq(%i[enum])
    expect(described_class.option_schema[:enum][:type]).to eq([Array])
  end

  describe 'FS-B58 coercion' do
    it 'keeps Symbols, converts Strings, maps nil to nil' do
      expect(type.coerce(:a)).to eq(:a)
      expect(type.coerce('before')).to eq(:before)
      expect(type.coerce('')).to eq(:'')
      expect(type.coerce(nil)).to be_nil
    end

    it 'raises TypeError naming only the class' do
      expect { type.coerce(1) }.to raise_error(TypeError, 'expected Symbol or String, got Integer')
      expect { type.coerce({}) }.to raise_error(TypeError, 'expected Symbol or String, got Hash')
    end
  end

  it 'FS-B33: missing only for nil' do
    expect(type.missing?(nil)).to be(true)
    expect(type.missing?(:'')).to be(false)
  end
end

RSpec.describe FieldStruct::Types::Value do
  subject(:type) { described_class.new }

  it 'FS-B164: ruby_type is Object and there are no options' do
    expect(type.ruby_type).to eq(Object)
    expect(described_class.option_schema).to eq({})
  end

  it 'FS-B70: returns input untouched' do
    obj = Object.new
    ['', [], false, 0, obj].each { |v| expect(type.coerce(v)).to equal(v) }
    expect(type.coerce(nil)).to be_nil
  end

  it 'FS-B70 / FS-B33: missing only for nil' do
    expect(type.missing?(nil)).to be(true)
    ['', [], false].each { |v| expect(type.missing?(v)).to be(false) }
  end
end

RSpec.describe 'FieldStruct.types scalar registrations' do
  {
    string: FieldStruct::Types::String,
    immutable_string: FieldStruct::Types::ImmutableString,
    integer: FieldStruct::Types::Integer,
    float: FieldStruct::Types::Float,
    big_decimal: FieldStruct::Types::BigDecimal,
    decimal: FieldStruct::Types::BigDecimal,
    boolean: FieldStruct::Types::Boolean,
    symbol: FieldStruct::Types::Symbol,
    value: FieldStruct::Types::Value
  }.each do |name, klass|
    it "registers :#{name}" do
      expect(FieldStruct.types.lookup(name)).to equal(klass)
    end
  end

  it 'FS-I16: every scalar type coerces nil to nil' do
    %i[string immutable_string integer float big_decimal boolean symbol value].each do |name|
      expect(FieldStruct.types.lookup(name).new.coerce(nil)).to be_nil
    end
  end

  it 'FS-I5: no scalar message echoes a distinctive secret input' do
    secret = 'S3CR3T-XYZ'
    %i[integer float big_decimal boolean symbol].each do |name|
      type = FieldStruct.types.lookup(name).new
      [secret, secret.to_sym, [secret], { secret => 1 }, Struct.new(:secret).new(secret)].each do |value|
        type.coerce(value)
      rescue ArgumentError, TypeError, RangeError => e
        chain = []
        error = e
        while error
          chain << error.message
          error = error.cause
        end
        expect(chain.join).not_to include(secret)
      end
    end
  end
end
