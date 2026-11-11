# frozen_string_literal: true

# Baseline performance workloads for actionable-tools. Run from this directory:
#   bundle exec ruby [--yjit] benchmarks/perf.rb
ENV['PERF_GEM'] ||= 'actionable-tools'
require 'bigdecimal'
require_relative '../lib/actionable/tools'
require_relative '../lib/actionable/tools/mcp'
require_relative '../../../benchmarks/perf/harness'

class LookUpOrder < Actionable::Action
  input do
    required :sku, :string, description: 'Product SKU'
    required :qty, :integer, in: 1..1000
    required :unit_price, :decimal, round: 2
    required :customer_email, :email
    required :tenant_id, :integer
    optional :coupon, :string, enum: %w[SAVE FREE]
  end
  output do
    required :total, :decimal, round: 2
    required :reference, :string
  end
  fails :out_of_stock, 'not enough stock', retry: false

  step :check_stock
  step :price
  step :finalize

  private

  def check_stock
    fail!(:out_of_stock) if input.qty > 500
  end

  def price = @total = input.unit_price * input.qty * BigDecimal('1.08')
  def finalize = @reference = "T#{input.tenant_id}-#{input.sku}"
end

CONTEXT = { tenant_id: ->(source) { source[:tenant_id] } }.freeze
SOURCE = { tenant_id: 7 }.freeze
ARGS = { 'sku' => 'SKU-1', 'qty' => 3, 'unit_price' => '19.99', 'customer_email' => 'ana@example.com' }.freeze
BAD_ARGS = ARGS.merge('qty' => 900).freeze
INVALID_ARGS = ARGS.merge('qty' => 'x', 'customer_email' => 'nope').freeze

TOOL = Actionable::Tools.definition(LookUpOrder, description: 'Look up an order', context: CONTEXT)
MCP_TOOL = Actionable::Tools::MCP.tool(LookUpOrder, description: 'Look up an order', context: CONTEXT)
SERVER = MCP::Server.new(name: 'bench', tools: [MCP_TOOL], server_context: SOURCE)
REQUEST = { jsonrpc: '2.0', id: 1, method: 'tools/call',
            params: { name: 'look_up_order', arguments: ARGS.transform_keys(&:to_sym) } }.freeze
REQUEST_JSON = Oj.dump(REQUEST, mode: :compat).freeze
raise 'tool call failed' unless TOOL.call(ARGS, SOURCE)['status'] == 'success'
raise 'mcp call failed' if SERVER.handle(REQUEST)[:result][:isError]

Perf.workload('Definition build (cold: schema + envelope)') do
  Actionable::Tools.definition(LookUpOrder, description: 'Look up an order', context: CONTEXT)
end
Perf.workload('call, success') { TOOL.call(ARGS, SOURCE) }
Perf.workload('call, declared failure') { TOOL.call(BAD_ARGS, SOURCE) }
Perf.workload('call, invalid input') { TOOL.call(INVALID_ARGS, SOURCE) }
Perf.workload('MCP round trip: server.handle(tools/call)') { SERVER.handle(REQUEST) }
Perf.workload('MCP round trip, JSON in/out (parse + handle + dump)') do
  Oj.dump(SERVER.handle(Oj.load(REQUEST_JSON, symbol_keys: true)), mode: :compat)
end
