# frozen_string_literal: true

RSpec.describe FieldStruct::JSONSchema, 'decimals: (JS-B24)' do
  let(:decimal_string) { { 'type' => 'string', 'pattern' => described_class::DECIMAL_PATTERN } }

  before do
    stub_const('Appraisal', struct do
      required :estimate, :big_decimal
      optional :history, :array, of: :big_decimal
      optional :by_room, :hash, of: :big_decimal
      optional :either, :union, of: %i[big_decimal string]
    end)
    stub_const('Lot', struct { required :appraisal, Appraisal })
  end

  it 'follows to_json by default' do
    props = described_class.generate(Appraisal)['properties']
    expect(props['estimate']).to eq('type' => 'number')
    expect(props['history']['items']).to eq('type' => %w[number null])
    expect(described_class.generate(Appraisal, decimals: :to_json)).to eq(described_class.generate(Appraisal))
  end

  it 'describes every decimal as the as_json string under decimals: :string, nested definitions included' do
    props = described_class.generate(Appraisal, decimals: :string)['properties']
    expect(props['estimate']).to eq(decimal_string)
    expect(props['history']['items']).to eq('type' => %w[string null], 'pattern' => described_class::DECIMAL_PATTERN)
    expect(props['by_room']['additionalProperties']).to eq('type' => %w[string null], 'pattern' => described_class::DECIMAL_PATTERN)
    expect(props['either']['anyOf']).to include(decimal_string)
    defs = described_class.generate(Lot, decimals: :string)['$defs']
    expect(defs['Appraisal']['properties']['estimate']).to eq(decimal_string)
  end

  it 'caches the two forms apart' do
    described_class.generate(Appraisal, decimals: :string)
    expect(described_class.generate(Appraisal)['properties']['estimate']).to eq('type' => 'number')
    expect(described_class.generate(Appraisal, decimals: :string)['properties']['estimate']).to eq(decimal_string)
  end

  it 'refuses any other value' do
    expect { described_class.generate(Appraisal, decimals: :text) }.to raise_error(
      ArgumentError, 'FieldStruct::JSONSchema.generate: decimals: takes :to_json or :string, got :text'
    )
  end
end
