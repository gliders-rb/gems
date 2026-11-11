# frozen_string_literal: true

RSpec.describe 'step spans' do
  let(:run_span) { span_named('HiveInspection.run') }

  def run_names = children_of(run_span).map(&:name)

  it 'OT-B10, OT-B14: every executed step and hook is a child span, in execution order' do
    define_inspection
    HiveInspection.run
    expect(run_names).to eq(%w[HiveInspection/open_hive HiveInspection/count_frames HiveInspection/file_report HiveInspection/stamp_log])
  end

  it 'OT-B10: attributes name the action, step, kind and section' do
    define_inspection
    HiveInspection.run
    span = span_named('HiveInspection/file_report')
    expect(span.kind).to eq(:internal)
    expect(span.attributes).to eq('actionable.action' => 'HiveInspection', 'actionable.step' => 'file_report',
                                  'actionable.step.kind' => 'method', 'actionable.section' => 'success')
    expect(span_named('HiveInspection/open_hive').attributes['actionable.section']).to eq('main')
    expect(span_named('HiveInspection/stamp_log').attributes['actionable.section']).to eq('always')
  end

  it 'OT-B15: success trace' do
    define_inspection
    HiveInspection.run
    sections = children_of(run_span).to_h { |s| [s.name, s.attributes['actionable.section']] }
    expect(sections).to eq('HiveInspection/open_hive' => 'main', 'HiveInspection/count_frames' => 'main',
                           'HiveInspection/file_report' => 'success', 'HiveInspection/stamp_log' => 'always')
  end

  it 'OT-B15, OT-B12: queenless trace, failure hook instead of success hook, code on the halting step' do
    define_inspection(queenless: true)
    HiveInspection.run
    expect(run_names).to eq(%w[HiveInspection/open_hive HiveInspection/count_frames HiveInspection/reseal_hive HiveInspection/stamp_log])
    expect(span_named('HiveInspection/reseal_hive').attributes['actionable.section']).to eq('failure')
    charge = span_named('HiveInspection/count_frames')
    expect(charge.attributes['actionable.code']).to eq('queen_missing')
    expect(charge.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
    expect(run_span.status.description).to eq('queen_missing')
  end

  it 'OT-B12: a step that only sets state has no code; one that records has it' do
    stub_const('Quote', Class.new(Actionable::Action) do
      step :compute
      step :confirm
      define_method(:compute) { @total = 1 }
      define_method(:confirm) { succeed('done') }
    end)
    Quote.run
    expect(span_named('Quote/compute').attributes).not_to have_key('actionable.code')
    expect(span_named('Quote/confirm').attributes['actionable.code']).to eq('success')
  end

  it 'OT-B12: a hook that leaves the result alone has no code' do
    define_inspection
    HiveInspection.run
    expect(span_named('HiveInspection/stamp_log').attributes).not_to have_key('actionable.code')
  end

  it 'OT-B10: guard-skipped steps get no span' do
    stub_const('Guarded', Class.new(Actionable::Action) do
      step :always_on
      step :never, if: ->(_a) { false }
      define_method(:always_on) { nil }
      define_method(:never) { nil }
    end)
    Guarded.run
    expect(spans.map(&:name)).to contain_exactly('Guarded.run', 'Guarded/always_on')
  end

  it 'OT-B10: step spans get error status but no exception event when a step raises' do
    define_inspection(raise_in: :charge)
    expect { HiveInspection.run }.to raise_error(ArgumentError)
    step = span_named('HiveInspection/count_frames')
    expect(step.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    expect(step.events).to be_nil.or be_empty
  end

  it 'OT-B13: step_spans = false emits run spans only; nil means off and the setter returns its argument' do
    define_inspection
    expect(Actionable::Otel.step_spans?).to be(true)
    expect((Actionable::Otel.step_spans = nil)).to be_nil
    expect(Actionable::Otel.step_spans?).to be(false)
    HiveInspection.run
    expect(spans.map(&:name)).to eq(['HiveInspection.run'])
    Actionable::Otel.step_spans = true
    expect(Actionable::Otel.step_spans?).to be(true)
  end

  it 'OT-B13: false is off too' do
    Actionable::Otel.step_spans = false
    expect(Actionable::Otel.step_spans?).to be(false)
  end

  it 'OT-B11, OT-B10: action steps and case steps' do
    stub_const('Child', Class.new(Actionable::Action) do
      step :work
      define_method(:work) { nil }
    end)
    stub_const('Router', Class.new(Actionable::Action) do
      input { required :mode, :string }
      step Child
      case_step :mode do
        on 'a', :route_a
        default :route_other
      end
      define_method(:mode) { input.mode }
      define_method(:route_a) { nil }
      define_method(:route_other) { nil }
    end)
    Router.run(mode: 'a')
    run = span_named('Router.run')
    kids = children_of(run)
    expect(kids.map(&:name)).to eq(%w[Router/Child Router/mode])
    expect(kids[0].attributes).to include('actionable.step' => 'Child', 'actionable.step.kind' => 'action')
    expect(kids[1].attributes).to include('actionable.step' => 'mode', 'actionable.step.kind' => 'case')
    expect(spans.map(&:name)).not_to include('Router/route_a')
    child_run = span_named('Child.run')
    expect(child_run.parent_span_id).to eq(kids[0].span_id)
    expect(children_of(child_run).map(&:name)).to eq(['Child/work'])
  end

  it 'OT-B10: an anonymous nested action step is named Actionable::Action' do
    inner = Class.new(Actionable::Action) { step(:x) }
    inner.send(:define_method, :x) { nil }
    stub_const('Outer', Class.new(Actionable::Action) { step(inner) })
    Outer.run
    expect(span_named('Outer/Actionable::Action').attributes['actionable.step']).to eq('Actionable::Action')
  end

  it 'OT-B10: an anonymous action labels its steps Actionable::Action/<name>' do
    klass = Class.new(Actionable::Action) { step(:go) }
    klass.send(:define_method, :go) { nil }
    klass.run
    expect(span_named('Actionable::Action/go').attributes['actionable.action']).to eq('Actionable::Action')
  end

  it 'OT-B5: history is unchanged by step spans' do
    define_inspection
    HiveInspection.measure :all
    expect(HiveInspection.run.history.steps.map(&:name)).to eq(%i[open_hive count_frames file_report stamp_log])
  end
end

RSpec.describe 'prepared step spans' do
  def klass_with_step
    Class.new(Actionable::Action) do
      step :sweep

      def sweep = nil
    end
  end

  it 'builds the span name and attributes once per step, label and section, and hands each span its own Hash' do
    stub_const('Apiary', klass_with_step)
    Apiary.run
    first = span_named('Apiary/sweep')
    OTEL_EXPORTER.reset
    expect(Actionable::Otel).not_to receive(:build_step_span)
    Apiary.run
    second = span_named('Apiary/sweep')
    expect(second.attributes).to eq(first.attributes)
    expect(second.attributes).not_to equal(first.attributes)
  end

  it 'follows a class that is named after its first run, and a subclass that shares the steps' do
    klass = klass_with_step
    klass.run
    expect(span_named('Actionable::Action/sweep').attributes['actionable.action']).to eq('Actionable::Action')
    OTEL_EXPORTER.reset
    stub_const('LateName', klass)
    stub_const('Child', Class.new(klass))
    klass.run
    Child.run
    expect(span_named('LateName/sweep').attributes['actionable.action']).to eq('LateName')
    expect(span_named('Child/sweep').attributes['actionable.action']).to eq('Child')
  end

  it 'OT-B10: follows a nested action step class that is named after its first run' do
    inner = klass_with_step
    stub_const('Smoker', Class.new(Actionable::Action) { step(inner) })
    Smoker.run
    expect(span_named('Smoker/Actionable::Action').attributes['actionable.step']).to eq('Actionable::Action')
    OTEL_EXPORTER.reset
    stub_const('Bellows', inner)
    Smoker.run
    expect(span_named('Smoker/Bellows').attributes).to include('actionable.action' => 'Smoker', 'actionable.step' => 'Bellows')
    OTEL_EXPORTER.reset
    expect(Actionable::Otel).not_to receive(:build_step_span)
    Smoker.run
    expect(span_named('Smoker/Bellows').attributes['actionable.step']).to eq('Bellows')
  end
end
