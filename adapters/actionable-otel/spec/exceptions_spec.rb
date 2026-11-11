# frozen_string_literal: true

RSpec.describe 'exceptions' do
  let(:run_span) { span_named('HiveInspection.run') }
  let(:events) { run_span.events || [] }

  before { define_inspection(raise_in: :charge) }

  def run_raising = HiveInspection.run(hive_tag: '4111111111111111')

  it 'OT-B19, OT-I3: re-raises the same exception and records it once on the run span, with no outcome or code' do
    raised = nil
    begin
      run_raising
    rescue ArgumentError => e
      raised = e
    end
    expect(raised).to be_a(ArgumentError)
    expect(events.size).to eq(1)
    expect(run_span.attributes.keys).to eq(['actionable.action'])
    expect(run_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
  end

  it 'OT-B19: a non-StandardError exception is recorded and re-raised too' do
    stub_const('Dying', Class.new(Actionable::Action) do
      step :go
      define_method(:go) { raise Interrupt }
    end)
    expect { Dying.run }.to raise_error(Interrupt)
    expect(span_named('Dying.run').events.size).to eq(1)
  end

  it 'OT-B20: type_only records the class name and nothing else' do
    expect { run_raising }.to raise_error(ArgumentError)
    event = events.first
    expect(event.name).to eq('exception')
    expect(event.attributes).to eq('exception.type' => 'ArgumentError')
  end

  it 'OT-B20: an anonymous exception class falls back to to_s' do
    klass = Class.new(StandardError)
    stub_const('Odd', Class.new(Actionable::Action) do
      step :go
      define_method(:go) { raise klass }
    end)
    expect { Odd.run }.to raise_error(klass)
    expect(span_named('Odd.run').events.first.attributes).to eq('exception.type' => klass.to_s)
  end

  it 'OT-B20: full records one event with message and stacktrace' do
    Actionable::Otel.exception_details = :full
    expect { run_raising }.to raise_error(ArgumentError)
    expect(events.size).to eq(1)
    expect(events.first.attributes.keys).to include('exception.type', 'exception.message', 'exception.stacktrace')
  end

  it 'OT-B21: anything else raises ArgumentError and leaves the setting unchanged' do
    expect { Actionable::Otel.exception_details = :message }
      .to raise_error(ArgumentError, 'Actionable::Otel.exception_details must be :type_only or :full, got :message')
    expect(Actionable::Otel.exception_details).to eq(:type_only)
    expect(Actionable::Otel::EXCEPTION_DETAILS).to be_frozen.and eq(%i[type_only full])
  end

  it 'OT-B22, OT-B41, OT-I1: no hive tag appears anywhere in any span' do
    expect { run_raising }.to raise_error(ArgumentError, /frame counter jammed/)
    expect(spans.inspect).not_to include('4111111111111111')
  end

  it 'OT-B40: the core DefinitionError still passes through' do
    stub_const('Bad', Class.new(Actionable::Action) do
      step :go
      define_method(:go) { @result = 'oops' }
    end)
    expect { Bad.run }.to raise_error(Actionable::DefinitionError, /@result is reserved/)
  end
end
