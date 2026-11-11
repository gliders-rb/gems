# frozen_string_literal: true

module SectionSpy
  private

  def record(section, step, &block)
    Thread.current[:section_log]&.push([section, step.name, step.kind])
    super
  end
end

RSpec.describe 'Action lifecycle hooks' do
  # Builds an action whose methods log their name into +log+ and whose bodies come from +bodies+.
  def logged_action(log, bodies = {}, &config)
    build_action do
      class_eval(&config) if config
      (steps.to_a + success_hooks.to_a + failure_hooks.to_a + skip_hooks.to_a + always_hooks.to_a).map(&:name).uniq.each do |name|
        body = bodies[name]
        define_method(name) do
          log << name
          instance_exec(&body) if body
        end
        private name
      end
    end
  end

  describe 'dispatch' do
    it 'AC-B#lifecycle: on_success runs only after a success; always runs last; declaration order' do
      log = []
      action = logged_action(log) do
        step :main
        on_success :s1
        on_failure :f1
        on_skip :k1
        on_success :s2
        always :a1
      end
      expect(action.run).to be_success
      expect(log).to eq(%i[main s1 s2 a1])
    end

    it 'AC-B#lifecycle: on_failure runs only after a failure, on_skip only after a skip' do
      log = []
      failing = logged_action(log, main: -> { fail!(:bad) }) do
        step :main
        on_success :s1
        on_failure :f1
        on_skip :k1
        always :a1
      end
      expect(failing.run).to be_failure
      expect(log).to eq(%i[main f1 a1])
      log.clear
      skipping = logged_action(log, main: -> { skip!(:later) }) do
        step :main
        on_success :s1
        on_failure :f1
        on_skip :k1
        always :a1
      end
      expect(skipping.run).to be_skipped
      expect(log).to eq(%i[main k1 a1])
    end

    it 'AC-B#lifecycle: a hook whose guard opts out is skipped' do
      log = []
      action = logged_action(log) do
        step :main
        on_success :s1, if: :no
        on_success :s2, unless: :no
        always :a1, if: :no
        define_method(:no) { false }
      end
      action.run
      expect(log).to eq(%i[main s2])
    end

    it 'AC-B#lifecycle: auto-success picks the success category' do
      log = []
      logged_action(log) { on_success(:s1) }.run
      expect(log).to eq(%i[s1])
    end
  end

  describe 'hook verbs' do
    it 'AC-B#hookverbs: a plain verb replaces the result and the remaining hooks still run' do
      log = []
      action = logged_action(log, s1: -> { fail(:late) }) do
        on_success :s1
        on_success :s2
        always :a1
      end
      result = action.run
      expect(result.code).to eq(:late)
      expect(log).to eq(%i[s1 s2 a1])
    end

    it 'AC-B#hookverbs: a bang verb adopts the result, stops its category, and always still sees it' do
      log = []
      seen = []
      action = logged_action(log, s1: -> { fail!(:late) }, a1: -> { seen << result.code }) do
        step :main
        on_success :s1
        on_success :s2
        always :a1
      end
      result = action.run
      expect(result).to be_failure
      expect(result.code).to eq(:late)
      expect(log).to eq(%i[main s1 a1])
      expect(seen).to eq([:late])
    end

    it 'AC-B#hookverbs: halt! in a hook keeps the current result and stops the phase' do
      log = []
      action = logged_action(log, s1: -> { halt! }) do
        step :main
        on_success :s1
        on_success :s2
        always :a1
      end
      result = action.run
      expect(result).to be_success
      expect(log).to eq(%i[main s1 a1])
    end

    it 'AC-B#recovery: succeed! in on_failure recovers; no on_success hook runs afterwards' do
      log = []
      action = logged_action(log, main: -> { fail!(:bad) }, f1: -> { succeed!('recovered') }) do
        step :main
        on_failure :f1
        on_failure :f2
        on_success :s1
        always :a1
      end
      result = action.run
      expect(result).to be_success
      expect(result.message).to eq('recovered')
      expect(log).to eq(%i[main f1 a1])
    end

    it 'AC-B#alwayshalt: a halt in an always hook stops only the remaining always hooks' do
      log = []
      action = logged_action(log, a1: -> { skip!(:enough) }) do
        step :main
        on_success :s1
        always :a1
        always :a2
      end
      result = action.run
      expect(result).to be_skipped
      expect(log).to eq(%i[main s1 a1])
    end

    it 'AC-B#exceptionhooks: a raising hook propagates and later hooks, always included, never run' do
      log = []
      action = logged_action(log, s1: -> { raise 'kraken' }) do
        on_success :s1
        on_success :s2
        always :a1
      end
      expect { action.run }.to raise_error(RuntimeError, 'kraken')
      expect(log).to eq(%i[s1])
    end

    it 'AC-I2: a raising step skips every hook' do
      log = []
      action = logged_action(log, main: -> { raise 'kraken' }) do
        step :main
        always :a1
      end
      expect { action.run }.to raise_error(RuntimeError, 'kraken')
      expect(log).to eq(%i[main])
    end
  end

  describe 'output through hooks' do
    it 'AC-B#hookoutput: an ivar a hook sets is captured by the refresh that follows it' do
      action = build_action do
        output do
          required :fare, :integer
          optional :sent, :boolean
        end
        step :compute
        on_success :notify
        private

        def compute = @fare = 3
        def notify = @sent = true
      end
      result = action.run
      expect([result.fare, result.sent]).to eq([3, true])
    end

    it 'AC-B#hookoutput: a hook that corrupts a valid output flips the run to invalid_output' do
      action = build_action do
        output { required :fare, :integer }
        step :compute
        on_success :corrupt
        private

        def compute = @fare = 3
        def corrupt = @fare = 'abc'
      end
      result = action.run
      expect(result).to be_failure
      expect(result.code).to eq(:invalid_output)
    end

    it 'AC-B#kwargswin: succeed keywords survive the refresh after every hook' do
      action = build_action do
        output { required :fare, :integer }
        step :compute
        on_success :touch
        always :touch
        private

        def compute
          @fare = 1
          succeed(fare: 99)
        end

        def touch = @other = 1
      end
      expect(action.run.fare).to eq(99)
    end

    it 'AC-B#invalidoutstays: later hooks keep the invalid output' do
      action = build_action do
        output { required :fare, :integer }
        step :noop
        on_failure :late
        always :late
        private

        def noop = nil
        def late = @fare = 5
      end
      result = action.run
      expect(result.code).to eq(:invalid_output)
      expect(result.output.valid?).to be(false)
      expect(result.errors[:fare]).to eq(['is required'])
    end
  end

  describe 'declaration' do
    it 'AC-B#redeclare: a hook is replaced in place, per list' do
      action = build_action do
        on_success :a, if: :one
        on_success :b
        on_success :a, if: :two
        always :a
      end
      expect(action.success_hooks.map(&:name)).to eq(%i[a b])
      expect(action.success_hooks.first.options).to eq(if: :two)
      expect(action.always_hooks.map(&:name)).to eq(%i[a])
      expect(action.failure_hooks).to be_empty
      expect(action.skip_hooks).to be_empty
    end

    it 'AC-B#snapshot: hooks are copied at subclass creation, per list' do
      parent = build_action { on_failure :f }
      child = build_action(parent) { always :a }
      parent.on_failure :late
      expect(child.failure_hooks.map(&:name)).to eq(%i[f])
      expect(child.failure_hooks).not_to equal(parent.failure_hooks)
      expect(parent.always_hooks).to be_empty
      expect(child.always_hooks.map(&:name)).to eq(%i[a])
    end

    it 'AC-B#subclassoverride: a subclass redeclaring a hook changes only its copy' do
      parent = build_action { on_success :a, if: :old }
      child = build_action(parent) { on_success :a, if: :new }
      expect(child.success_hooks.first.options).to eq(if: :new)
      expect(parent.success_hooks.first.options).to eq(if: :old)
    end

    it 'AC-B#stepdecl: hook targets obey the step target rules' do
      expect { build_action.on_success(5) }.to raise_error(ArgumentError, 'unsupported step target: 5')
    end
  end

  describe 'missing methods' do
    it 'AC-B#missingmethod: hook methods must exist' do
      action = build_action do
        step :a
        on_success :b
        always :c
        def a = nil
      end
      expect { action.run }.to raise_error(Actionable::DefinitionError, /declares step\(s\) calling :b, :c but does not implement them/)
    end

    it 'AC-B#missingmethod: Kernel methods do not count and the check ignores guards' do
      action = build_action { always :exit, if: -> { false } }
      expect { action.run }.to raise_error(Actionable::DefinitionError, /:exit/)
    end
  end

  describe 'the record seam' do
    before { Actionable::Runner.prepend(SectionSpy) }

    after { Thread.current[:section_log] = nil }

    it 'AC-B#recordseam: hooks record with their section; only the picked category and unguarded hooks' do
      Thread.current[:section_log] = []
      log = []
      action = logged_action(log, main: -> { skip!(:later) }) do
        step :main
        on_success :s1
        on_skip :k1
        on_skip :k2, if: :no
        on_failure :f1
        always :a1
        define_method(:no) { false }
      end
      action.run
      expect(Thread.current[:section_log]).to eq([
                                                   %i[main main method],
                                                   %i[skip k1 method],
                                                   %i[always a1 method]
                                                 ])
    end

    it 'AC-B#recordseam: a halting hook still had its record call opened' do
      Thread.current[:section_log] = []
      log = []
      action = logged_action(log, s1: -> { halt! }) do
        on_success :s1
        on_success :s2
        always :a1
      end
      action.run
      expect(Thread.current[:section_log].map(&:first)).to eq(%i[success always])
    end
  end
end
