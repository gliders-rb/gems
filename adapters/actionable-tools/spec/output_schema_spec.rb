# frozen_string_literal: true

require 'json_schemer'

RSpec.describe 'Actionable::Tools output schema' do
  def schema_for(action, **options)
    Actionable::Tools.definition(action, description: 'x', **options).output_schema
  end

  let(:schema) { schema_for(Tides::RecalibrateGauge, context: { operator_id: ->(_) {} }) }
  let(:validator) { JSONSchemer.schema(schema) }

  def envelope(overrides = {})
    { 'status' => 'success', 'code' => 'success', 'message' => nil, 'output' => {}, 'errors' => {}, 'metadata' => {} }.merge(overrides)
  end

  it 'AT-B15: is an object schema over the six keys' do
    expect(schema['$schema']).to eq(FieldStruct::JSONSchema::DRAFT)
    expect(schema['type']).to eq('object')
    expect(schema['required']).to eq(Actionable::Tools::RESULT_KEYS)
    expect(schema['properties'].keys).to eq(Actionable::Tools::RESULT_KEYS)
    props = schema['properties']
    expect(props['status']).to eq('enum' => %w[success failure skipped])
    expect(props['message']).to eq('type' => %w[string null])
    expect(props['output']).to eq({})
    expect(props['errors']).to eq('type' => 'object', 'additionalProperties' => { 'type' => 'array', 'items' => { 'type' => 'string' } })
    expect(props['metadata']).to eq('type' => 'object')
  end

  it 'AT-B15: RESULT_KEYS is not shared with the schema' do
    expect(schema['required']).not_to equal(Actionable::Tools::RESULT_KEYS)
  end

  it 'AT-B16: describes the code with declared failures and skips' do
    expect(schema['properties']['code']).to eq(
      'type' => 'string',
      'description' => '"success", or why the run failed or was skipped. Declared failures: out_of_tolerance. ' \
                       'Declared skips: already_calibrated. "invalid_input" means the arguments were rejected; see errors.'
    )
  end

  it 'AT-B16: leaves out the declared lists when there are none' do
    description = schema_for(Tides::Probe)['properties']['code']['description']
    expect(description).to eq('"success", or why the run failed or was skipped. ' \
                              '"invalid_input" means the arguments were rejected; see errors.')
  end

  it 'AT-B17: with an output schema, output follows it only on success, and $defs are lifted' do
    expect(schema['if']).to eq('properties' => { 'status' => { 'const' => 'success' } })
    output = schema.dig('then', 'properties', 'output')
    expect(output).not_to have_key('$schema')
    expect(output).not_to have_key('$defs')
    expect(output['required']).to eq(%w[record_id offset_mm])
    expect(schema['$defs'].keys).to eq(['Tides::Mooring'])
    expect(schema['properties']['output']).to eq({})
  end

  it 'AT-B17: no $defs key when the output has none' do
    action = Class.new(Actionable::Action) do
      output { required :id, :string }
      input { required :q, :string }
    end
    expect(schema_for(action, name: 'x')).not_to have_key('$defs')
  end

  it 'AT-B18: without an output schema there is no if/then and output is any' do
    free = schema_for(Tides::Probe)
    expect(free['properties']['output']).to eq({})
    expect(free).not_to include('if', 'then')
  end

  it 'AT-B19: is valid 2020-12 and accepts every kind of envelope' do
    expect(JSONSchemer.valid_schema?(schema)).to be(true)
    ok = envelope('output' => { 'record_id' => 'cal', 'offset_mm' => '12.5', 'moored_at' => nil })
    expect(validator.valid?(ok)).to be(true)
    failure = envelope('status' => 'failure', 'code' => 'out_of_tolerance', 'message' => 'no', 'metadata' => { 'kind' => 'rejected' })
    expect(validator.valid?(failure)).to be(true)
    invalid = envelope('status' => 'failure', 'code' => 'invalid_input', 'message' => 'x', 'errors' => { 'offset_mm' => ['is invalid'] })
    expect(validator.valid?(invalid)).to be(true)
    expect(validator.valid?(envelope('status' => 'skipped', 'code' => 'already_calibrated'))).to be(true)
  end

  it 'AT-B19: rejects a success whose output lacks the required fields, but not a failure' do
    expect(validator.valid?(envelope)).to be(false)
    expect(validator.valid?(envelope('status' => 'failure', 'code' => 'out_of_tolerance'))).to be(true)
  end

  it 'AT-B19: rejects an envelope missing a key or with an unknown status' do
    expect(validator.valid?(envelope('status' => 'weird'))).to be(false)
    expect(validator.valid?(envelope.except('errors'))).to be(false)
  end
end
