# frozen_string_literal: true

RSpec.describe 'run spans' do
  def attrs(span) = span.attributes

  it 'OT-B1: a run is one internal span named <Label>.run with actionable.action' do
    define_inspection
    HiveInspection.run
    span = span_named('HiveInspection.run')
    expect(span.kind).to eq(:internal)
    expect(attrs(span)['actionable.action']).to eq('HiveInspection')
  end

  it 'OT-B1: an anonymous action is labelled Actionable::Action' do
    klass = Class.new(Actionable::Action) { step(:go) }
    klass.send(:define_method, :go) { nil }
    klass.run
    span = span_named('Actionable::Action.run')
    expect(attrs(span)['actionable.action']).to eq('Actionable::Action')
  end

  it 'OT-B1: a run that returns an invalid-input failure without reaching its steps still gets a span' do
    stub_const('Strict', Class.new(Actionable::Action) do
      input { required :isbn, :string }
      step :go
      define_method(:go) { nil }
    end)
    result = Strict.run
    span = span_named('Strict.run')
    expect(result.code).to eq(:invalid_input)
    expect(attrs(span).slice('actionable.outcome', 'actionable.code')).to eq('actionable.outcome' => 'failure',
                                                                             'actionable.code' => 'invalid_input')
  end

  it 'OT-B2: success sets outcome and code' do
    define_inspection
    HiveInspection.run
    expect(attrs(span_named('HiveInspection.run')).slice('actionable.outcome', 'actionable.code'))
      .to eq('actionable.outcome' => 'success', 'actionable.code' => 'success')
  end

  it 'OT-B2, OT-B3: a declared failure carries its code and an error status with the code as description' do
    define_inspection(queenless: true)
    HiveInspection.run
    span = span_named('HiveInspection.run')
    expect(attrs(span).slice('actionable.outcome', 'actionable.code'))
      .to eq('actionable.outcome' => 'failure', 'actionable.code' => 'queen_missing')
    expect(span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    expect(span.status.description).to eq('queen_missing')
    expect(span.events).to be_nil.or be_empty
  end

  it 'OT-B2, OT-B3: a skip is not an error' do
    stub_const('Idle', Class.new(Actionable::Action) do
      skips :no_hive_due
      step :go
      define_method(:go) { skip!(:no_hive_due) }
    end)
    Idle.run
    span = span_named('Idle.run')
    expect(attrs(span).slice('actionable.outcome', 'actionable.code'))
      .to eq('actionable.outcome' => 'skipped', 'actionable.code' => 'no_hive_due')
    expect(span.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
  end

  it 'OT-B3: success leaves the status unset' do
    define_inspection
    HiveInspection.run
    expect(span_named('HiveInspection.run').status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
  end

  it 'OT-B4: run_each yields one run span per item' do
    define_inspection
    HiveInspection.run_each([{}, {}])
    expect(spans_named('HiveInspection.run').size).to eq(2)
  end

  it 'OT-B5, OT-I3: the result and its history are the core result' do
    define_inspection
    HiveInspection.measure :all
    result = HiveInspection.run
    expect(result).to be_success
    expect(result.history.steps.map(&:name)).to eq(%i[open_hive count_frames file_report stamp_log])
  end

  it 'OT-B6: a core RSpec stub emits no span' do
    define_inspection
    allow_actionable_success(HiveInspection)
    HiveInspection.run
    expect(spans).to be_empty
  end
end
