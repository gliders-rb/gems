# frozen_string_literal: true

RSpec.describe Actionable::Tools do
  def define(action = Tides::RecalibrateGauge, **options)
    described_class.definition(action, description: 'Recalibrate a gauge', **options)
  end

  it 'AT-I8: the core require loads neither mcp nor ruby_llm' do
    code = "require 'actionable/tools'; abort 'loaded' if defined?(::MCP) || defined?(::RubyLLM)"
    expect(system(RbConfig.ruby, '-Ilib', '-e', code)).to be(true)
  end

  it 'exposes the version and the result keys' do
    expect(Actionable::Tools::VERSION).to eq('1.0.0.pre1')
    expect(described_class::RESULT_KEYS).to eq(%w[status code message output errors metadata])
    expect(described_class::RESULT_KEYS).to be_frozen
  end

  describe 'building (AT-B1..B8)' do
    it 'AT-B1: refuses a discriminated input' do
      expect { define(Tides::RouteFeed) }.to raise_error(
        ArgumentError, 'Tides::RouteFeed has a discriminated input (input_for), which has no single schema yet'
      )
    end

    it 'AT-B2: refuses an action with no input schema' do
      expect { define(Tides::Heartbeat) }.to raise_error(ArgumentError, 'Tides::Heartbeat has no input schema; tools need one')
    end

    it 'AT-B3: refuses a blank or missing description' do
      [' ', nil, ''].each do |text|
        expect { described_class.definition(Tides::RecalibrateGauge, description: text) }
          .to raise_error(ArgumentError, 'Tides::RecalibrateGauge: a tool needs a description')
      end
    end

    it 'AT-B4: refuses a context field the input does not have, naming all of them' do
      expect { define(context: { station: proc {} }) }
        .to raise_error(ArgumentError, 'Tides::RecalibrateGauge has no input field station to take from context')
      expect { define(context: { station: proc {}, zone: proc {} }) }
        .to raise_error(ArgumentError, 'Tides::RecalibrateGauge has no input field station, zone to take from context')
    end

    it 'AT-B1..B3: checks in order' do
      expect { described_class.definition(Tides::RouteFeed, description: '') }.to raise_error(ArgumentError, /discriminated/)
      expect { described_class.definition(Tides::Heartbeat, description: '') }.to raise_error(ArgumentError, /no input schema/)
    end

    it 'AT-B5: names a tool from the last class-name segment, snake cased' do
      expect(define.name).to eq('recalibrate_gauge')
      expect(define(Harbor::RecalibrateGauge).name).to eq('recalibrate_gauge')
      expect(define(HTTPClient).name).to eq('http_client')
      expect(define(Gauge2Buoy).name).to eq('gauge2_buoy')
    end

    it 'AT-B5: takes an explicit name, and treats nil as default' do
      expect(define(name: 'tides.recalibrate').name).to eq('tides.recalibrate')
      expect(define(name: nil).name).to eq('recalibrate_gauge')
    end

    it 'AT-B5: an anonymous action needs a name' do
      anonymous = Class.new(Actionable::Action) { input { required :id, :string } }
      expect { define(anonymous) }.to raise_error(ArgumentError, 'an anonymous action needs name:')
      expect(define(anonymous, name: 'lookup').name).to eq('lookup')
    end

    it 'AT-B6: symbolizes and freezes the context' do
      definition = define(context: { 'operator_id' => ->(_) { 1 } })
      context = definition.instance_variable_get(:@context)
      expect(context.keys).to eq([:operator_id])
      expect(context).to be_frozen
    end

    it 'AT-B7: stores annotations as given, freezing the caller\'s hash, without validating keys' do
      hints = { destructive: true, whatever: 1 }
      definition = define(annotations: hints)
      expect(definition.annotations).to equal(hints)
      expect(hints).to be_frozen
    end

    it 'AT-B8/AT-I7: is frozen, and keeps the description as given' do
      definition = define(Tides::RecalibrateGauge)
      expect(definition).to be_frozen
      expect(definition.action).to eq(Tides::RecalibrateGauge)
      expect(described_class.definition(Tides::RecalibrateGauge, description: ' padded ').description).to eq(' padded ')
    end

    it 'AT-I1: has no registry-wide entry point' do
      expect(described_class).not_to respond_to(:all)
      expect(described_class).not_to respond_to(:definitions)
    end
  end
end
