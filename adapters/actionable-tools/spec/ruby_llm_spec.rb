# frozen_string_literal: true

require 'actionable/tools/ruby_llm'

RSpec.describe Actionable::Tools::RubyLLM do
  let(:operator) { Struct.new(:id).new(7) }
  let(:klass) do
    described_class.tool(Tides::RecalibrateGauge, description: 'Shift a gauge zero point by an offset',
                                                  context: { operator_id: lambda(&:id) })
  end
  let(:tool) { klass.new(operator) }

  it 'AT-B40: builds a RubyLLM::Tool subclass named after the definition' do
    expect(klass.superclass).to eq(RubyLLM::Tool)
    expect(klass.tool_name).to eq('recalibrate_gauge')
    expect(described_class.tool(Tides::RecalibrateGauge, description: 'x', name: 'tides.recalibrate').tool_name).to eq('tides.recalibrate')
  end

  it 'AT-B41: exposes name, description and the parameters schema' do
    expect(tool.name).to eq('recalibrate_gauge')
    expect(tool.description).to eq('Shift a gauge zero point by an offset')
    expect(tool.parameters_schema['required']).to eq(%w[gauge_id offset_mm])
    expect(tool.parameters_schema['properties'].keys).to eq(%w[gauge_id offset_mm cause moored_at])
  end

  it 'AT-B41: call returns the envelope Hash, with the constructed source passed to the context proc' do
    seen = []
    action = Class.new(Actionable::Action) do
      input { required :operator_id, :integer }
      step :see
      define_method(:see) { seen << input.operator_id }
    end
    described_class.tool(action, name: 'whoami', description: 'x', context: { operator_id: lambda(&:id) }).new(operator).call
    expect(seen).to eq([7])
    result = tool.call(gauge_id: 'g1', offset_mm: '12.50')
    expect(result).to include('status' => 'success')
    expect(result['output']).to include('record_id' => 'cal_g1')
    expect(result.keys).to eq(Actionable::Tools::RESULT_KEYS)
  end

  it 'AT-B41: a failure is returned, not raised' do
    expect(tool.call(gauge_id: 'g1', offset_mm: '200.0')).to include('status' => 'failure', 'code' => 'out_of_tolerance')
  end

  it 'AT-I3: a model-sent context field is overwritten' do
    expect(tool.call(gauge_id: 'g1', offset_mm: '5.0', operator_id: 999)).to include('status' => 'success')
  end

  it 'AT-B42: approval is off by default and on when asked' do
    expect(klass.requires_approval?).to be(false)
    approved = described_class.tool(Tides::RecalibrateGauge, description: 'x', approval: true)
    expect(approved.requires_approval?).to be(true)
    expect(approved.new.requires_approval?).to be(true)
  end

  it 'AT-B22: exceptions propagate' do
    built = described_class.tool(Tides::Glitch, description: 'x').new
    expect { built.call(n: 1) }.to raise_error(KeyError, 'sensor fault')
  end

  it 'AT-B43: requiring it without the ruby_llm gem raises a LoadError naming the gem' do
    code = <<~RUBY
      $LOAD_PATH.unshift('lib')
      module Kernel
        alias_method :real_require, :require
        def require(name) = name == 'ruby_llm' ? raise(LoadError, 'cannot load such file -- ruby_llm') : real_require(name)
      end
      begin
        require 'actionable/tools/ruby_llm'
      rescue LoadError => e
        puts e.message
      end
    RUBY
    output = IO.popen([RbConfig.ruby, '-e', code], err: %i[child out], &:read)
    expect(output.strip).to eq("actionable/tools/ruby_llm needs the ruby_llm gem: add `gem 'ruby_llm', '~> 2.1'` to your Gemfile")
  end
end
