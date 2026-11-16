# frozen_string_literal: true

RSpec.describe 'avro: keys (AV-B16)' do
  def field_with(avro)
    FieldStruct::Field.new(name: :v, type: FieldStruct::Types::String, avro: avro)
  end

  let(:keys) { 'it takes type:, scale:, precision:, timestamp:, enum:, enum_default:' }

  it 'refuses a misspelled key, suggesting the one it most likely meant' do
    expect { FieldStruct::Avro::Options.read(field_with({ scal: 2 })) { 'Buoy#depth' } }
      .to raise_error(ArgumentError, "FieldStruct::Avro (Buoy#depth) avro: has no key scal: (did you mean scale:?); #{keys}")
  end

  it 'refuses a key nothing is close to, without a suggestion' do
    expect { FieldStruct::Avro::Options.read(field_with({ doc: 'depth in fathoms' })) { 'Buoy#depth' } }
      .to raise_error(ArgumentError, "FieldStruct::Avro (Buoy#depth) avro: has no key doc:; #{keys}")
  end

  it 'takes every key it reads, as Symbols or Strings' do
    all = { type: nil, 'scale' => 2, precision: 9, timestamp: :millis, enum: false, enum_default: :calm }
    expect(FieldStruct::Avro::Options.read(field_with(all)).keys).to eq(%i[type scale precision timestamp enum enum_default])
  end

  it 'reports the struct field when building a schema' do
    stub_const('Buoy', Class.new(FieldStruct::Base) { required :depth, :decimal, avro: { scal: 2 } })
    expect { FieldStruct::Avro.schema(Buoy) }.to raise_error(ArgumentError, /\AFieldStruct::Avro \(Buoy#depth\) avro: has no key scal:/)
  end
end
