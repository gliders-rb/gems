# frozen_string_literal: true

RSpec.describe 'length: in JSON Schema (JS-B10)' do
  it 'writes minLength and maxLength from the finite ends' do
    stub_const('Pennant', Class.new(FieldStruct::Base) do
      required :motto, :string, length: 3..40
      optional :hoist, :string, length: ..8
      optional :fly, :string, length: 2...6
      optional :colors, :array, of: :string, element: { length: 1.. }
    end)
    props = FieldStruct::JSONSchema.generate(Pennant)['properties']
    expect(props['motto']).to eq('type' => 'string', 'minLength' => 3, 'maxLength' => 40)
    expect(props['hoist']).to eq('type' => %w[string null], 'maxLength' => 8)
    expect(props['fly']).to eq('type' => %w[string null], 'minLength' => 2, 'maxLength' => 5)
    expect(props['colors']['items']).to eq('type' => %w[string null], 'minLength' => 1)
  end
end

RSpec.describe 'length: on :binary in JSON Schema (JS-B10)' do
  it 'keeps only maxLength, since bytes are not JSON characters' do
    stub_const('Fragment', Class.new(FieldStruct::Base) { required :chunk, :binary, length: 2..16 })
    expect(FieldStruct::JSONSchema.generate(Fragment)['properties']['chunk']).to eq('type' => 'string', 'maxLength' => 16)
  end
end
