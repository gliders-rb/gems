# frozen_string_literal: true

RSpec.describe FieldStruct::Avro::Options do
  def field_with(avro)
    FieldStruct::Field.new(name: :v, type: FieldStruct::Types::String, avro: avro)
  end

  let(:named) { Struct.new(:label) }

  it 'AV-B16: reads no option, nil and a Hash, without building the label' do
    expect(described_class.read(FieldStruct::Field.new(name: :v, type: FieldStruct::Types::String)) { raise 'label built' }).to eq({})
    expect(described_class.read(field_with(nil)) { raise 'label built' }).to eq({})
    expect(described_class.read(field_with({ type: 'long' })) { raise 'label built' }).to eq({ type: 'long' })
  end

  it 'AV-B16: refuses an avro: that is not a Hash' do
    expect { described_class.read(field_with('string')) { 'Loose#v' } }.to raise_error(
      ArgumentError, "FieldStruct::Avro (Loose#v) avro: takes a Hash of options, like avro: {type: 'string'}, got \"string\""
    )
  end

  it 'AV-B53: reads a field once and hits the cache on repeat' do
    field = field_with({ 'type' => 'long' })
    first = described_class.read(field)
    expect(first).to eq({ type: 'long' })
    expect(described_class.read(field)).to equal(first)
  end

  it 'AV-B53: a redeclared field gets fresh options' do
    old = field_with({ type: 'long' })
    fresh = field_with({ type: 'string' })
    described_class.read(old)
    expect(described_class.read(fresh)).to eq({ type: 'string' })
  end

  it 'AV-B53: changing the options in place is not noticed' do
    opts = { type: 'long' }
    field = field_with(opts)
    described_class.read(field)
    opts[:type] = 'string'
    expect(described_class.read(field)).to eq({ type: 'long' })
  end

  it 'AV-B53: a refused avro: is refused again on every read' do
    field = field_with('string')
    2.times { expect { described_class.read(field) { 'Loose#v' } }.to raise_error(ArgumentError, /Loose#v/) }
  end

  it 'AV-B16: treats type: nil as no override' do
    expect(described_class.override({ type: nil })).to be_nil
    expect(described_class.override({ type: :string })).to eq(:string)
  end

  it 'AV-B16: turns Symbols into Strings deeply' do
    expect(described_class.stringify({ type: :array, items: [:null, { type: :string }] }))
      .to eq({ 'type' => 'array', 'items' => ['null', { 'type' => 'string' }] })
  end

  it 'AV-B17: passes everything but type: to elements and members' do
    expect(described_class.nested({ type: 'x', timestamp: :millis, scale: 2 })).to eq({ timestamp: :millis, scale: 2 })
  end

  it 'AV-B6: takes the field timestamp over the call and refuses a bad one' do
    expect(described_class.timestamp({}, :micros, named.new('K#t'))).to eq(:micros)
    expect(described_class.timestamp({ timestamp: :nanos }, :micros, named.new('K#t'))).to eq(:nanos)
    expect { described_class.timestamp({ timestamp: :seconds }, :micros, named.new('K#t')) }.to raise_error(
      ArgumentError, 'FieldStruct::Avro (K#t) avro: {timestamp:} must be one of [:micros, :nanos, :millis], got :seconds'
    )
  end

  it 'AV-B16: refuses a non-Hash avro: option the same way from to_datum' do
    klass = define_struct('Loose') { required :v, :string, avro: 'string' }
    expect { FieldStruct::Avro.to_datum(klass.new(v: 'x')) }.to raise_error(ArgumentError, /Loose#v\) avro: takes a Hash/)
    expect { FieldStruct::Avro.schema(klass) }.to raise_error(ArgumentError, /Loose#v\) avro: takes a Hash/)
  end
end
