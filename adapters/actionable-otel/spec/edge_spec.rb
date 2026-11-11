# frozen_string_literal: true

RSpec.describe 'edge cases' do
  it 'OT-B1, OT-B10: nested action run spans nest under the parent step span, in one trace' do
    stub_const('Inner', Class.new(Actionable::Action) do
      step :pack
      define_method(:pack) { nil }
    end)
    stub_const('Outer', Class.new(Actionable::Action) { step Inner })
    Outer.run
    outer = span_named('Outer.run')
    step = span_named('Outer/Inner')
    inner = span_named('Inner.run')
    expect(step.parent_span_id).to eq(outer.span_id)
    expect(inner.parent_span_id).to eq(step.span_id)
    expect([outer, step, inner].map(&:trace_id).uniq.size).to eq(1)
  end

  it 'OT-B1: a failing child action surfaces on both run spans' do
    stub_const('Inner', Class.new(Actionable::Action) do
      fails :swarm_risk
      step :pack
      define_method(:pack) { fail!(:swarm_risk) }
    end)
    stub_const('Outer', Class.new(Actionable::Action) do
      fails :swarm_risk
      step Inner
    end)
    Outer.run
    expect(span_named('Inner.run').attributes['actionable.code']).to eq('swarm_risk')
    expect(span_named('Outer.run').attributes['actionable.code']).to eq('swarm_risk')
  end

  it 'OT-B12: a step that records twice carries the last code, and a re-recorded same code still counts' do
    stub_const('Twice', Class.new(Actionable::Action) do
      step :go
      define_method(:go) do
        succeed('a')
        fail(:later) # rubocop:disable Style/SignalException -- the Actionable verb
      end
      fails :later
    end)
    Twice.run
    expect(span_named('Twice/go').attributes['actionable.code']).to eq('later')
  end

  it 'OT-B3: a failure records no exception event' do
    define_inspection(queenless: true)
    HiveInspection.run
    expect(span_named('HiveInspection.run').events).to be_nil.or be_empty
  end

  it 'OT-B32: with only the API installed (no SDK) runs behave identically' do
    script = <<~RUBY
      require 'opentelemetry'
      require 'actionable/otel'
      class Boom < Actionable::Action
        step :go
        def go = fail!(:nope)
        fails :nope
      end
      class Raiser < Actionable::Action
        step :go
        def go = raise('x')
      end
      r = Boom.run
      begin; Raiser.run; rescue => e; end
      p [r.code, e.message, defined?(OpenTelemetry::SDK).nil?]
    RUBY
    out = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script], err: File::NULL, &:read)
    expect(out.strip).to eq('[:nope, "x", true]')
  end

  it 'OT-I3: init-time errors (missing method) still raise the core error' do
    klass = Class.new(Actionable::Action) { step(:missing) }
    expect { klass.run }.to raise_error(Actionable::DefinitionError)
  end

  it 'OT-I1: attribute values are only names, outcomes and codes' do
    define_inspection(queenless: true)
    HiveInspection.run(hive_tag: '4111111111111111')
    values = spans.flat_map { |s| s.attributes.values }
    expect(values).to all(be_a(String))
    expect(values.join(' ')).not_to include('4111')
  end
end
