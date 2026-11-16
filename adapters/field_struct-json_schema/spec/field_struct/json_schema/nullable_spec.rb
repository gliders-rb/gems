# frozen_string_literal: true

RSpec.describe 'A required nullable field in JSON Schema (JS-B6)' do
  it 'stays in required and accepts null' do
    stub_const('Tideline', Class.new(FieldStruct::Base) do
      required :station, :string
      required :ebb_at, :integer, nullable: true
    end)
    schema = FieldStruct::JSONSchema.generate(Tideline)
    expect(schema['required']).to eq(%w[station ebb_at])
    expect(schema['properties']['ebb_at']).to eq('type' => %w[integer null])
    expect(schema['properties']['station']).to eq('type' => 'string')
  end
end
