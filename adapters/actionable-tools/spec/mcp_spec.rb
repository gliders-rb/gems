# frozen_string_literal: true

require 'actionable/tools/mcp'
require 'json_schemer'

RSpec.describe Actionable::Tools::MCP do
  let(:calls) { [] }
  let(:tool) do
    described_class.tool(Tides::RecalibrateGauge, description: 'Shift a gauge zero point by an offset',
                                                  context: { operator_id: ->(server_context) { server_context[:operator_id] } },
                                                  annotations: { destructive: true, idempotent: false })
  end
  let(:server) do
    config = MCP::Configuration.new(validate_tool_call_results: true)
    MCP::Server.new(name: 'tides', tools: [tool], server_context: { operator_id: 7 }, configuration: config)
  end

  def rpc(method, params = {}, id: 1)
    server.handle({ jsonrpc: '2.0', id: id, method: method, params: params })
  end

  def call_tool(arguments)
    rpc('tools/call', { name: 'recalibrate_gauge', arguments: arguments })
  end

  it 'AT-B30: maps hints and returns nil for none' do
    expect(described_class.annotations({})).to be_nil
    expect(described_class.annotations({ destructive: true, idempotent: false })).to eq(destructive_hint: true, idempotent_hint: false)
    expect(described_class::HINTS).to eq(read_only: :read_only_hint, destructive: :destructive_hint, idempotent: :idempotent_hint,
                                         open_world: :open_world_hint)
    expect(described_class::HINTS).to be_frozen
  end

  it 'AT-B30: rejects unknown hints at build time' do
    expect { described_class.tool(Tides::RecalibrateGauge, description: 'x', annotations: { safe: true, wild: 1 }) }.to raise_error(
      ArgumentError, 'unknown annotations: safe, wild (known: read_only, destructive, idempotent, open_world)'
    )
  end

  it 'AT-B31: builds an MCP::Tool subclass' do
    expect(tool.superclass).to eq(MCP::Tool)
    expect(tool.name_value).to eq('recalibrate_gauge')
  end

  it 'AT-B32: tools/list shows name, description, schemas and annotations' do
    listed = rpc('tools/list')[:result][:tools].first
    expect(listed[:name]).to eq('recalibrate_gauge')
    expect(listed[:description]).to eq('Shift a gauge zero point by an offset')
    schemas = listed.values_at(:inputSchema, :outputSchema)
    expect(schemas.map { |schema| schema[:required] }).to eq([%w[gauge_id offset_mm], Actionable::Tools::RESULT_KEYS])
    expect(listed[:annotations]).to include(idempotentHint: false, destructiveHint: true)
  end

  it 'AT-B32/B31: a success is not an error, with the same JSON in content and structuredContent' do
    result = call_tool({ gauge_id: 'g1', offset_mm: '12.50' })[:result]
    expect(result[:isError]).to be(false)
    expect(result[:structuredContent]['output']).to include('record_id' => 'cal_g1')
    text = result[:content].first
    expect(text[:type]).to eq('text')
    expect(Oj.load(text[:text], mode: :compat)).to eq(Oj.load(Oj.dump(result[:structuredContent], mode: :compat), mode: :compat))
  end

  it 'AT-B32: a declared failure is an error result, a skip is not' do
    failure = call_tool({ gauge_id: 'g1', offset_mm: '200.0' })[:result]
    expect(failure[:isError]).to be(true)
    expect(failure[:structuredContent]).to include('code' => 'out_of_tolerance')
    skipped = call_tool({ gauge_id: 'stale', offset_mm: '1.0' })[:result]
    expect(skipped[:isError]).to be(false)
    expect(skipped[:structuredContent]).to include('status' => 'skipped')
  end

  it 'AT-I3: the server context fills the context field, whatever the model sends' do
    seen = []
    action = Class.new(Actionable::Action) do
      input { required :operator_id, :integer }
      step :see
      define_method(:see) { seen << input.operator_id }
    end
    built = described_class.tool(action, name: 'whoami', description: 'x', context: { operator_id: ->(ctx) { ctx[:operator_id] } })
    MCP::Server.new(name: 's', tools: [built], server_context: { operator_id: 7 })
               .handle({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'whoami', arguments: { operator_id: 999 } } })
    expect(seen).to eq([7])
  end

  it 'AT-B32: arguments violating the input schema are rejected before the action runs' do
    allow(Tides::RecalibrateGauge).to receive(:run).and_call_original
    result = call_tool({ gauge_id: 'g1', offset_mm: 12.5 })[:result]
    expect(result[:isError]).to be(true)
    expect(Tides::RecalibrateGauge).not_to have_received(:run)
  end

  it 'AT-B32: a missing required argument is rejected too' do
    expect(call_tool({ gauge_id: 'g1' })[:result][:isError]).to be(true)
  end

  it 'AT-B22: an exception becomes an internal error response' do
    built = described_class.tool(Tides::Glitch, description: 'x')
    boom = MCP::Server.new(name: 's', tools: [built])
    response = boom.handle({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'glitch', arguments: { n: 1 } } })
    expect(response[:error][:message]).to match(/Internal error/)
  end

  it 'AT-B33: requiring it without the mcp gem raises a LoadError naming the gem' do
    code = <<~RUBY
      $LOAD_PATH.unshift('lib')
      module Kernel
        alias_method :real_require, :require
        def require(name) = name == 'mcp' ? raise(LoadError, 'cannot load such file -- mcp') : real_require(name)
      end
      begin
        require 'actionable/tools/mcp'
      rescue LoadError => e
        puts e.message
      end
    RUBY
    output = IO.popen([RbConfig.ruby, '-e', code], err: %i[child out], &:read)
    expect(output.strip).to eq("actionable/tools/mcp needs the mcp gem: add `gem 'mcp', '~> 1.8'` to your Gemfile")
  end
end
