# frozen_string_literal: true

module ReturnSpy
  private

  def record(section, step, &block)
    before = @instance.result
    value = super
    Thread.current[:return_log]&.push([section, step.name, value, before, @instance.result])
    value
  end
end

RSpec.describe 'Measurement and history' do
  def measured(mode = :all, rate: nil, parent: Actionable::Action, &)
    build_action(parent) do
      measure(mode, **{ rate: rate }.compact)
      class_eval(&)
    end
  end

  it 'AC-B#measurenone: the default records nothing' do
    result = build_action { step(:a) && nil }.tap { |k| k.define_method(:a) { nil } }.run
    expect(result.history).to eq([])
  end

  it 'AC-B#historyentries: one entry per executed step or hook, in order, with the documented fields' do
    action = measured do
      step :a
      step :skipped, if: :no
      step :b
      on_success :hook
      always :tail
      define_method(:no) { false }
      %i[a skipped b hook tail].each { |n| define_method(n) { nil } }
      private :no, :a, :skipped, :b, :hook, :tail
    end
    history = action.run.history
    expect(history).to be_a(Actionable::History)
    expect(history.steps.map { |s| [s.section, s.name] }).to eq(
      [%i[main a], %i[main b], %i[success hook], %i[always tail]]
    )
    entry = history.steps.first
    expect(entry.started_at).to be_a(Time)
    expect(entry.duration).to be_a(Float)
    expect(entry.nested).to be_nil
    expect(history.took).to be >= 0
  end

  it 'AC-B#historyentries: the failure and skip hook sections' do
    failing = measured do
      step :sail
      on_failure :react
      define_method(:sail) { fail!(:bad) }
      define_method(:react) { nil }
      private :sail, :react
    end
    skipping = measured do
      step :sail
      on_skip :react
      define_method(:sail) { skip!(:later) }
      define_method(:react) { nil }
      private :sail, :react
    end
    expect(failing.run.history.steps.map(&:section)).to eq(%i[main failure])
    expect(skipping.run.history.steps.map(&:section)).to eq(%i[main skip])
  end

  it 'AC-B#historycode: set only when the step changed the recorded result (identity)' do
    action = measured do
      step :ivar_only
      step :records
      step :records_again
      step :nothing
      on_success :hook_fail
      define_method(:ivar_only) { @x = 1 }
      define_method(:records) { succeed('x') }
      define_method(:records_again) { succeed('x') }
      define_method(:nothing) { nil }
      define_method(:hook_fail) { fail!(:late) }
      private :ivar_only, :records, :records_again, :nothing, :hook_fail
    end
    expect(action.run.history.steps.map(&:code)).to eq([nil, :success, :success, nil, :late])
  end

  it 'AC-B#historyentries: a halting step is still appended, with its code' do
    action = measured do
      step :stop
      step :never
      define_method(:stop) { fail!(:halted) }
      define_method(:never) { nil }
      private :stop, :never
    end
    steps = action.run.history.steps
    expect(steps.map { |s| [s.name, s.code] }).to eq([%i[stop halted]])
  end

  it 'AC-B#historyentries: a raising step still gets its entry (default record body)' do
    action = measured { step(:kraken) && nil }
    action.class_eval do
      define_method(:kraken) { raise 'x' }
      private :kraken
    end
    instance = action.new
    runner = Actionable::Runner.new(instance)
    runner.instance_variable_set(:@measuring, true)
    runner.instance_variable_set(:@history, Actionable::History.new)
    expect { runner.__send__(:record, :main, action.steps.first) { raise 'x' } }.to raise_error('x')
    expect(runner.instance_variable_get(:@history).steps.map(&:name)).to eq([:kraken])
  end

  describe 'nested runs' do
    let(:child) do
      named_action('MeasuredChild') do
        step :work

        private

        def work = sleep(0.01)
      end
    end

    it 'AC-B#cascade: a measuring parent makes the child measure; the child history is nested on the step entry' do
      child
      parent = measured do
        step MeasuredChild
        step :tail
        define_method(:tail) { nil }
        private :tail
      end
      steps = parent.run.history.steps
      expect(steps.map(&:name)).to eq([MeasuredChild, :tail])
      nested = steps.first.nested
      expect(nested).to be_a(Actionable::History)
      expect(nested.steps.map(&:name)).to eq([:work])
      expect(steps.first.duration).to be >= nested.took
    end

    it 'AC-B#cascade: the child result keeps its own history too' do
      child
      holder = []
      parent = measured do
        step :grab
        define_method(:grab) { holder << MeasuredChild.run }
        private :grab
      end
      parent.run
      expect(holder.first.history).to be_a(Actionable::History)
    end

    it 'AC-B#cascade: an action hook is nested on the hook entry' do
      child
      parent = measured { on_success MeasuredChild }
      entry = parent.run.history.steps.first
      expect([entry.section, entry.name]).to eq([:success, MeasuredChild])
      expect(entry.nested.steps.map(&:name)).to eq([:work])
    end

    it 'AC-B#cascade: run_each items inside a measuring run measure too' do
      child
      holder = []
      parent = measured do
        step :batch
        define_method(:batch) { holder.concat(MeasuredChild.run_each([{}, {}]).to_a) }
        private :batch
      end
      parent.run
      expect(holder.map { |r| r.history.class }).to eq([Actionable::History, Actionable::History])
    end

    it 'AC-B#cascade: a non-measuring parent does not cascade' do
      child
      parent = build_action { step(MeasuredChild) && nil }
      result = parent.run
      expect(result.history).to eq([])
      only = build_action { step MeasuredChild }
      expect(only.run.history).to eq([])
    end

    it 'AC-B#cascade: a child measuring on its own under a non-measuring parent keeps its history to itself' do
      named_action('SelfMeasured') do
        measure :all
        step :work

        private

        def work = nil
      end
      holder = []
      parent = build_action do
        step :grab
        define_method(:grab) { holder << SelfMeasured.run }
        private :grab
      end
      expect(parent.run.history).to eq([])
      expect(holder.first.history.steps.size).to eq(1)
    end

    it 'AC-B#fiberlocal: a run inside another Fiber is not recorded and does not cascade' do
      child
      holder = []
      parent = measured do
        step :elsewhere
        define_method(:elsewhere) { holder << Fiber.new { MeasuredChild.run }.resume }
        private :elsewhere
      end
      parent.run
      expect(holder.first.history).to eq([])
    end

    it 'AC-B#fiberlocal: state is restored after each scope' do
      measured { step(:a) && nil }.class_eval { define_method(:a) { nil } }
      expect(Actionable::Measurement.recording?).to be(false)
      named_action('Restorer') do
        measure :all
        step :sail

        private

        def sail = nil
      end
      Restorer.run
      expect(Actionable::Measurement.recording?).to be(false)
    end
  end

  describe 'sampling and inheritance' do
    it 'AC-B#sampled: rate 1.0 always records, 0.0 never' do
      always = measured(:sampled, rate: 1.0) { step(:a) && nil }
      never = measured(:sampled, rate: 0.0) { step(:a) && nil }
      [always, never].each { |k| k.class_eval { define_method(:a) { nil } } }
      expect(always.run.history.steps.size).to eq(1)
      expect(never.run.history).to eq([])
    end

    it 'AC-B#sampled: a sampled-in run cascades like :all' do
      named_action('SampledChild') do
        step :work

        private

        def work = nil
      end
      parent = measured(:sampled, rate: 1.0) { step(SampledChild) && nil }
      expect(parent.run.history.steps.first.nested.steps.size).to eq(1)
    end

    it 'AC-B#measureinherit: mode and rate are inherited by snapshot' do
      parent = measured(:sampled, rate: 0.5) { nil }
      child = build_action(parent)
      expect([child.measure, child.measure_rate]).to eq([:sampled, 0.5])
    end
  end

  describe 'the record seam return and identity' do
    before { Actionable::Runner.prepend(ReturnSpy) }

    after { Thread.current[:return_log] = nil }

    %i[none all].each do |mode|
      it "AC-B#recordreturn: the value of the block comes back through record (measure #{mode})" do
        Thread.current[:return_log] = []
        action = measured(mode) do
          step :a
          define_method(:a) { :from_step }
          private :a
        end
        action.run
        expect(Thread.current[:return_log].first[2]).to eq(:from_step)
      end
    end

    it 'AC-B#resultidentity: a verb always changes identity, even to an equal result; ivars do not' do
      Thread.current[:return_log] = []
      action = measured(:none) do
        step :first
        step :same
        step :ivar
        define_method(:first) { succeed('x') }
        define_method(:same) { succeed('x') }
        define_method(:ivar) { @a = 1 }
        private :first, :same, :ivar
      end
      action.run
      log = Thread.current[:return_log]
      before_after = log.map { |entry| entry[3].equal?(entry[4]) }
      expect(before_after).to eq([false, false, true])
      expect(log[0][3]).to be_nil
      expect(log[1][3]).to eq(log[1][4])
    end
  end
end
