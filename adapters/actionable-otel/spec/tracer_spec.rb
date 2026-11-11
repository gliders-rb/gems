# frozen_string_literal: true

RSpec.describe Actionable::Otel do
  def fake_provider
    calls = []
    provider = Object.new
    provider.define_singleton_method(:tracer) do |*args|
      calls << args
      Object.new
    end
    [provider, calls]
  end

  it 'OT-B30: the tracer is named actionable at the adapter version' do
    described_class.tracer.in_span('probe') { nil }
    scope = spans.first.instrumentation_scope
    expect([scope.name, scope.version]).to eq(['actionable', Actionable::Otel::VERSION])
    expect(described_class::TRACER_NAME).to eq('actionable')
  end

  it 'OT-I6, OT-B31: the tracer is cached per provider' do
    provider, calls = fake_provider
    allow(OpenTelemetry).to receive(:tracer_provider).and_return(provider)
    first = described_class.tracer
    expect(described_class.tracer).to equal(first)
    expect(calls).to eq([['actionable', Actionable::Otel::VERSION]])
  end

  it 'OT-I5, OT-B31: a provider installed later applies to the next call' do
    one, = fake_provider
    two, calls_two = fake_provider
    allow(OpenTelemetry).to receive(:tracer_provider).and_return(one, one, two, two)
    a = described_class.tracer
    expect(described_class.tracer).to equal(a)
    b = described_class.tracer
    expect(b).not_to equal(a)
    expect(described_class.tracer).to equal(b)
    expect(calls_two.size).to eq(1)
  end

  it 'OT-B31: a concurrent caller during a slow fetch for a new provider never gets the old tracer' do
    old, = fake_provider
    allow(OpenTelemetry).to receive(:tracer_provider).and_return(old)
    old_tracer = described_class.tracer

    gate = Queue.new
    entered = Queue.new
    slow = Object.new
    slow.define_singleton_method(:tracer) do |*args|
      entered << true
      gate.pop
      Object.new.tap { |t| t.define_singleton_method(:args) { args } }
    end
    allow(OpenTelemetry).to receive(:tracer_provider).and_return(slow)

    first = Thread.new { described_class.tracer }
    entered.pop
    second = Thread.new { described_class.tracer }
    sleep 0.05
    gate << true
    gate << true
    results = [first.value, second.value]
    expect(results).to all(satisfy { |t| !t.equal?(old_tracer) })
  end

  it 'OT-B42: defaults in a fresh process' do
    script = 'require "opentelemetry"; require "actionable/otel"; ' \
             'p [Actionable::Otel.step_spans?, Actionable::Otel.exception_details]'
    out = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script], &:read)
    expect(out.strip).to eq('[true, :type_only]')
  end

  it 'OT-I2: requiring actionable alone never loads OpenTelemetry' do
    script = 'require "actionable"; p defined?(OpenTelemetry).nil?'
    out = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script], err: File::NULL, &:read)
    expect(out.strip).to eq('true')
  end
end
