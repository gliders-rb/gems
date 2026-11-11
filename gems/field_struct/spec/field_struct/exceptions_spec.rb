# frozen_string_literal: true

RSpec.describe 'FieldStruct exceptions' do
  it 'forms the documented hierarchy' do
    expect(FieldStruct::Error.superclass).to eq(StandardError)
    expect(FieldStruct::CoercionError.superclass).to eq(FieldStruct::Error)
    expect(FieldStruct::ImmutableError.superclass).to eq(FieldStruct::Error)
    expect(FieldStruct::UnknownAttributeError.superclass).to eq(FieldStruct::Error)
  end

  it 'CoercionError carries field_name and original' do
    original = ArgumentError.new('bad')
    error = FieldStruct::CoercionError.new('boom', field_name: :height, original: original)
    expect(error.message).to eq('boom')
    expect(error.field_name).to eq(:height)
    expect(error.original).to equal(original)
  end

  it 'CoercionError defaults field_name and original to nil' do
    error = FieldStruct::CoercionError.new('boom')
    expect([error.field_name, error.original]).to eq([nil, nil])
  end

  it 'UnknownAttributeError carries keys' do
    expect(FieldStruct::UnknownAttributeError.new('x', keys: %i[a b]).keys).to eq(%i[a b])
    expect(FieldStruct::UnknownAttributeError.new('x').keys).to eq([])
  end
end
