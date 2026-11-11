# frozen_string_literal: true

require 'json_schemer'

RSpec.describe 'Actionable::Tools::Definition#call' do
  let(:definition) do
    Actionable::Tools.definition(Tides::RecalibrateGauge, description: 'Recalibrate', context: { operator_id: lambda { |source|
      source[:operator_id]
    } })
  end
  let(:source) { { operator_id: 7 } }
  let(:validator) { JSONSchemer.schema(definition.output_schema) }

  def call(arguments) = definition.call(arguments, source)

  it 'AT-I2/B21a: a success is the six-key envelope in order' do
    result = call('gauge_id' => 'g1', 'offset_mm' => '12.50')
    expect(result).to eq(
      'status' => 'success', 'code' => 'success', 'message' => nil,
      'output' => { 'record_id' => 'cal_g1', 'offset_mm' => '12.5', 'moored_at' => nil }, 'errors' => {}, 'metadata' => {}
    )
    expect(result.keys).to eq(Actionable::Tools::RESULT_KEYS)
  end

  it 'AT-B21a: a declared failure carries code, message and metadata' do
    result = call('gauge_id' => 'g1', 'offset_mm' => '200.0')
    expect(result).to include('status' => 'failure', 'code' => 'out_of_tolerance', 'message' => 'offsets over 100 need a surveyor',
                              'metadata' => { 'kind' => 'rejected' })
    expect(result.keys).to eq(Actionable::Tools::RESULT_KEYS)
  end

  it 'AT-B21a: invalid input is a failure with errors' do
    result = call('gauge_id' => 'g1', 'offset_mm' => '0.0')
    expect(result).to include('status' => 'failure', 'code' => 'invalid_input', 'errors' => { 'offset_mm' => ['is invalid'] })
  end

  it 'AT-B21a: a skip is its own status' do
    result = call('gauge_id' => 'stale', 'offset_mm' => '1.0')
    expect(result).to include('status' => 'skipped', 'code' => 'already_calibrated')
    expect(result.keys).to eq(Actionable::Tools::RESULT_KEYS)
  end

  it 'AT-B21a: a nested struct comes out as a Hash' do
    result = call('gauge_id' => 'g1', 'offset_mm' => '5.0', 'moored_at' => { 'basin' => 'Cape Wren' })
    expect(result['output']['moored_at']).to eq('basin' => 'Cape Wren')
  end

  it 'AT-I3/B21a: a model-sent context field is ignored, the proc value wins' do
    seen = nil
    action = Class.new(Actionable::Action) do
      input { required :operator_id, :integer }
      step :see
      define_method(:see) { seen = input.operator_id }
    end
    tool = Actionable::Tools.definition(action, name: 'x', description: 'x', context: { operator_id: ->(src) { src[:operator_id] } })
    tool.call({ 'operator_id' => 999 }, source)
    expect(seen).to eq(7)
  end

  it 'AT-B20: accepts Symbol keys and keeps an unmapped name as a Symbol' do
    expect(call(gauge_id: 'g1', offset_mm: '5.0')).to include('status' => 'success')
    expect(call('gauge_id' => 'g1', 'offset_mm' => '5.0', 'bogus' => 1)['status']).to eq('success')
  end

  it 'AT-B20: maps external names back to field names, context overwriting even the external name' do
    tool = Actionable::Tools.definition(Tides::Remap, description: 'x', context: { station: ->(src) { src } })
    expect(tool.input_schema['properties'].keys).to eq(%w[peak_level])
    result = tool.call({ 'peak_level' => 5, 'site' => 'evil', 'station' => 'worse' }, 'north-pier')
    expect(result['output']).to eq('level' => 5, 'station' => 'north-pier')
  end

  it 'AT-B21: a context proc gets the source (nil by default)' do
    got = []
    action = Tides::RecalibrateGauge
    tool = Actionable::Tools.definition(action, description: 'x', context: { operator_id: ->(src) { (got << src) && 1 } })
    tool.call({ 'gauge_id' => 'o', 'offset_mm' => '1.0' })
    tool.call({ 'gauge_id' => 'o', 'offset_mm' => '1.0' }, :me)
    expect(got).to eq([nil, :me])
  end

  it 'AT-B19: every envelope validates against the output schema' do
    [{ 'gauge_id' => 'g1', 'offset_mm' => '12.50', 'moored_at' => { 'basin' => 'x' } }, { 'gauge_id' => 'g1', 'offset_mm' => '200.0' },
     { 'gauge_id' => 'g1', 'offset_mm' => '0.0' }, { 'gauge_id' => 'stale', 'offset_mm' => '1.0' }].each do |arguments|
      result = call(arguments)
      expect(validator.valid?(result)).to be(true), validator.validate(result).map { |e| e['error'] }.join("\n")
    end
  end

  it 'AT-B22/I6: exceptions propagate' do
    tool = Actionable::Tools.definition(Tides::Glitch, description: 'x')
    expect { tool.call({ 'n' => 1 }) }.to raise_error(KeyError, 'sensor fault')
  end

  it 'AT-B23: error? is true only for a failure' do
    expect(definition.error?(call('gauge_id' => 'g1', 'offset_mm' => '200.0'))).to be(true)
    expect(definition.error?(call('gauge_id' => 'g1', 'offset_mm' => '0.0'))).to be(true)
    expect(definition.error?(call('gauge_id' => 'stale', 'offset_mm' => '1.0'))).to be(false)
    expect(definition.error?(call('gauge_id' => 'g1', 'offset_mm' => '1.0'))).to be(false)
  end

  it 'AT-B24: a free-form output action passes its output through' do
    tool = Actionable::Tools.definition(Tides::Probe, description: 'Echo')
    expect(tool.call({ 'echo' => 'hi' })['output']).to eq('echo' => 'hi')
    expect(tool.output_schema.dig('properties', 'output')).to eq({})
  end
end
