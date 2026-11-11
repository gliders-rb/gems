# frozen_string_literal: true

require 'json_schemer'

RSpec.describe 'Actionable::Tools input schema' do
  let(:context) { { operator_id: ->(_) { 7 } } }
  let(:definition) { Actionable::Tools.definition(Tides::RecalibrateGauge, description: 'Recalibrate', context: context) }
  let(:schema) { definition.input_schema }

  it 'AT-B10/B12: starts from the generated schema, in declaration order, without context fields' do
    expect(schema['$schema']).to eq(FieldStruct::JSONSchema::DRAFT)
    expect(schema['properties'].keys).to eq(%w[gauge_id offset_mm cause moored_at])
    expect(schema['required']).to eq(%w[gauge_id offset_mm])
    expect(schema['$defs'].keys).to eq(['Tides::Mooring'])
  end

  it 'AT-B12: is a valid 2020-12 schema, and accepts and rejects the right arguments' do
    expect(JSONSchemer.valid_schema?(schema)).to be(true)
    validator = JSONSchemer.schema(schema)
    expect(validator.valid?({ 'gauge_id' => 'g1', 'offset_mm' => '12.50' })).to be(true)
    expect(validator.valid?({ 'gauge_id' => 'g1' })).to be(false)
  end

  it 'AT-B11: keeps required when nothing was removed, drops the key when it empties' do
    plain = Actionable::Tools.definition(Tides::RecalibrateGauge, description: 'Recalibrate').input_schema
    expect(plain['required']).to eq(%w[gauge_id offset_mm operator_id])
    only = Class.new(Actionable::Action) { input { required :operator_id, :integer } }
    empty = Actionable::Tools.definition(only, name: 'whoami', description: 'x', context: { operator_id: ->(_) {} }).input_schema
    expect(empty).not_to have_key('required')
    expect(empty['properties']).to eq({})
  end

  it 'AT-B11: removes an aliased field under its JSON name' do
    action = Class.new(Actionable::Action) do
      input do
        required :level, :integer
        required :basin, :string
        serialize :json, level: :peak_level
      end
    end
    schema = Actionable::Tools.definition(action, name: 'x', description: 'x', context: { level: ->(_) { 1 } }).input_schema
    expect(schema['properties'].keys).to eq(%w[basin])
    expect(schema['required']).to eq(%w[basin])
  end

  it 'AT-B11: keeps $defs even when only a removed field used one' do
    fillers = { operator_id: ->(_) {}, moored_at: ->(_) {} }
    schema = Actionable::Tools.definition(Tides::RecalibrateGauge, description: 'x', context: fillers).input_schema
    expect(schema['properties'].keys).to eq(%w[gauge_id offset_mm cause])
    expect(schema['$defs'].keys).to eq(['Tides::Mooring'])
  end

  it 'AT-B13: a big_decimal is a string, and ranges are not in the schema' do
    offset_mm = schema['properties']['offset_mm']
    expect(offset_mm['type']).to eq('string')
    expect(offset_mm).not_to include('minimum', 'maximum')
    validator = JSONSchemer.schema(schema)
    expect(validator.valid?({ 'gauge_id' => 'g1', 'offset_mm' => 12.5 })).to be(false)
    expect(validator.valid?({ 'gauge_id' => 'g1', 'offset_mm' => '0.00' })).to be(true)
  end

  it 'AT-B8: the schema is frozen shallowly' do
    expect(schema).to be_frozen
  end
end
