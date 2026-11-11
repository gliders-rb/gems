# frozen_string_literal: true

# Baseline performance workloads for actionable-otel: the same actions run untraced and traced (SDK with an
# in-memory exporter). Run from this directory:
#   bundle exec ruby [--yjit] benchmarks/perf.rb
# The untraced half has to run in its own process (requiring actionable/otel patches Action.run for good), so
# this script re-executes itself once with PERF_OTEL=off and writes a second result file,
# actionable-otel-untraced-*.json, before running the traced half.
untraced = ENV['PERF_OTEL'] == 'off'
ENV['PERF_GEM'] ||= untraced ? 'actionable-otel-untraced' : 'actionable-otel'

if !untraced && !ENV['PERF_PROFILE'] && !ENV['PERF_LIST'] && !ENV['PERF_NO_CHILD']
  flag = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? '--yjit' : '--disable-yjit'
  system({ 'PERF_OTEL' => 'off', 'PERF_GEM' => nil }, RbConfig.ruby, flag, __FILE__) || abort('untraced child failed')
end

require 'bigdecimal'
require_relative '../../../gems/actionable/lib/actionable'
require 'opentelemetry/sdk'
require_relative '../lib/actionable/otel' unless untraced
require_relative '../../../benchmarks/perf/harness'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
unless untraced
  OpenTelemetry::SDK.configure do |c|
    c.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER))
  end
end

module Nested
  class Quote < Actionable::Action
    input do
      required :sku, :string
      required :qty, :integer, in: 1..1000
      required :unit_price, :decimal, round: 2
    end
    output do
      required :total, :decimal, round: 2
      required :reference, :string
    end
    fails :swarm_risk, 'swarm risk too high'

    step :check_swarm
    step :price
    step :discount
    step :tax
    step :finalize

    private

    def check_swarm
      fail!(:swarm_risk) if input.qty > 500
    end

    def price = @subtotal = input.unit_price * input.qty
    def discount = @subtotal -= @subtotal * BigDecimal('0.1')
    def tax = @gross = @subtotal * BigDecimal('1.08')

    def finalize
      @total = @gross
      @reference = "Q-#{input.sku}"
    end
  end

  class Tax < Actionable::Action
    input { required :amount, :decimal, round: 2 }
    output { required :gross, :decimal, round: 2 }
    step :go

    private

    def go = @gross = input.amount * BigDecimal('1.08')
  end

  class QuoteNested < Actionable::Action
    input do
      required :qty, :integer
      required :unit_price, :decimal, round: 2
    end
    output { required :gross, :decimal, round: 2 }
    step :price
    step Tax, input: %i[amount], expose: %i[gross]

    private

    def price = @amount = input.unit_price * input.qty
  end
end

OK = { sku: 'SKU-1', qty: '3', unit_price: '19.99' }.freeze
FAIL = OK.merge(qty: '900').freeze
COUNTER = Struct.new(:n).new(0)

# The in-memory exporter keeps every finished span; drop them so a long run does not just measure the heap.
def drain!
  EXPORTER.reset if ((COUNTER.n += 1) % 500).zero?
end

Perf.workload('5-step run, success') { Nested::Quote.run(**OK).tap { drain! } }
Perf.workload('5-step run, declared failure') { Nested::Quote.run(**FAIL).tap { drain! } }
Perf.workload('nested action run') { Nested::QuoteNested.run(**OK).tap { drain! } }
unless untraced
  Perf.workload('5-step run, success, run span only (step_spans=false)') do
    Actionable::Otel.step_spans = false
    Nested::Quote.run(**OK).tap { drain! }
  ensure
    Actionable::Otel.step_spans = true
  end
end
