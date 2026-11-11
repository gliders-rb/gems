# frozen_string_literal: true

module RecordSpy
  private

  def record(section, step, &block)
    Thread.current[:record_log]&.push([section, step, @instance.class, @instance.result])
    super
  end
end

RSpec.describe Actionable::Action do
  describe 'step declaration' do
    it 'AC-B#stepdecl: step returns the ordered set; String and Symbol names are the same step' do
      action = build_action do
        step :a
        step 'a'
        step :b
      end
      expect(action.steps.map(&:name)).to eq(%i[a b])
      expect(action.steps).to be_a(Set)
    end

    it 'AC-B#stepdecl: unsupported targets raise ArgumentError' do
      action = build_action
      expect { action.step 5 }.to raise_error(ArgumentError, 'unsupported step target: 5')
      expect { action.step String }.to raise_error(ArgumentError, 'unsupported step target: String')
    end

    it 'AC-B#redeclare: replaces options in place and keeps the first position' do
      action = build_action do
        step :a, if: :one
        step :b
        step :a, if: :two
      end
      expect(action.steps.map(&:name)).to eq(%i[a b])
      expect(action.steps.first.options).to eq(if: :two)
    end

    it 'AC-B#redeclare: step options never take part in equality' do
      expect(Actionable::Steps::Method.new(:a, if: :x)).to eq(Actionable::Steps::Method.new(:a))
      expect(Actionable::Steps::Method.new(:a).hash).to eq(Actionable::Steps::Method.new(:a, unless: :y).hash)
      expect(Actionable::Steps::Method.new(:a)).not_to eq(Actionable::Steps::Method.new(:b))
    end
  end

  describe 'inheritance' do
    it 'AC-B#snapshot: steps are copied at subclass creation; later parent changes are not seen' do
      parent = build_action { step :a }
      child = build_action(parent)
      parent.step :late
      expect(child.steps.map(&:name)).to eq(%i[a])
      expect(parent.steps.map(&:name)).to eq(%i[a late])
      expect(child.steps).not_to equal(parent.steps)
    end

    it 'AC-B#subclassoverride: a subclass redeclaring changes only its copy, at the old position' do
      parent = build_action do
        step :a, if: :old
        step :b
      end
      child = build_action(parent) { step :a, if: :new }
      expect(child.steps.map(&:name)).to eq(%i[a b])
      expect(child.steps.first.options).to eq(if: :new)
      expect(parent.steps.first.options).to eq(if: :old)
    end

    it 'AC-B#registry: named subclasses register at creation; anonymous ones and later-named ones do not' do
      klass = Class.new(Actionable::Action)
      stub_const('LateNamed', klass)
      expect(Actionable.registry['LateNamed']).to be_nil
      class RegistryProbeAction < Actionable::Action; end
      expect(Actionable.registry['RegistryProbeAction']).to equal(RegistryProbeAction)
      expect(Actionable.registry[:RegistryProbeAction]).to equal(RegistryProbeAction)
    ensure
      Object.send(:remove_const, :RegistryProbeAction) if defined?(RegistryProbeAction)
    end
  end

  describe 'guards' do
    it 'AC-B#guards: if:/unless: take a method name (private ok) or a callable' do
      ran = []
      action = build_action do
        step :a, if: :yes
        step :b, if: :no
        step :c, unless: :yes
        step :d, if: lambda(&:flag)
        step :e, if: :yes, unless: :yes
        attr_reader :flag

        define_method(:initialize) { |flag: true| @flag = flag }
        %i[a b c d e].each { |name| define_method(name) { ran << name } }
        define_method(:yes) { true }
        define_method(:no) { false }
        private :a, :b, :c, :d, :e, :yes, :no
      end
      action.run(flag: false)
      expect(ran).to eq([:a])
      ran.clear
      action.run(flag: true)
      expect(ran).to eq(%i[a d])
    end

    it 'AC-B#guards: a missing guard method raises NoMethodError when evaluated' do
      action = build_action do
        step :a, if: :nowhere
        define_method(:a) { nil }
      end
      expect { action.run }.to raise_error(NoMethodError)
    end

    it 'AC-B#privatesteps: private step methods are invoked' do
      action = build_action do
        step :secret
        private

        def secret = succeed('private ok')
      end
      expect(action.run.message).to eq('private ok')
    end
  end

  describe 'running' do
    it 'AC-B#instances: every run builds a fresh instance' do
      action = build_action do
        step :count
        private

        def count
          @n = (@n || 0) + 1
          succeed(n: @n)
        end
      end
      expect([action.run.output, action.run.output]).to eq([{ n: 1 }, { n: 1 }])
    end

    it 'AC-B#freeformrun: .run forwards args and kwargs verbatim to the constructor' do
      action = build_action do
        step :sail
        define_method(:initialize) { |a, b = 2, c: 3| @all = [a, b, c] }
        define_method(:sail) { succeed(all: @all) }
        private :sail
      end
      expect(action.run(1, c: 9).output).to eq(all: [1, 2, 9])
      expect { action.run }.to raise_error(ArgumentError)
    end

    it 'AC-B#freeformrun: the default constructor accepts and ignores anything' do
      expect(build_action.run(1, 2, a: 3)).to be_success
    end

    it 'AC-B#runseam: Action.run is the public singleton entry and a prepended wrapper sees nested-free calls once' do
      calls = []
      wrapper = Module.new do
        define_method(:run) do |*args, **kwargs|
          calls << [args, kwargs]
          super(*args, **kwargs)
        end
      end
      action = build_action
      action.singleton_class.prepend(wrapper)
      result = action.run(1, a: 2)
      expect(calls).to eq([[[1], { a: 2 }]])
      expect(result).to be_success
    end

    it 'AC-B#runseam: every run_each item goes through run' do
      calls = []
      action = build_action
      action.singleton_class.prepend(Module.new do
        define_method(:run) do |*args, **kwargs|
          calls << [args, kwargs]
          super(*args, **kwargs)
        end
      end)
      action.run_each([{ a: 1 }, [2, 3], 4])
      expect(calls).to eq([[[], { a: 1 }], [[2, 3], {}], [[4], {}]])
    end
  end

  describe 'the record seam and runner instance' do
    # A prepended module cannot be removed, so the spy only records while the thread-local log exists.
    before { Actionable::Runner.prepend(RecordSpy) }

    after { Thread.current[:record_log] = nil }

    def log = Thread.current[:record_log]

    it 'AC-B#recordseam: one :main call per executed step, in order, with the step object itself' do
      Thread.current[:record_log] = []
      action = build_action do
        step :a
        step :b, if: :never
        step :c
        define_method(:a) { @x = 1 }
        define_method(:b) { raise 'unreachable' }
        define_method(:c) { succeed }
        define_method(:never) { false }
        private :a, :b, :c, :never
      end
      action.run
      expect(log.map { |entry| entry[0] }).to eq(%i[main main])
      expect(log.map { |entry| entry[1].name }).to eq(%i[a c])
      expect(log[0][1]).to equal(action.steps.first)
    end

    it 'AC-B#runnerinstance: @instance gives the action class and the result recorded so far' do
      Thread.current[:record_log] = []
      action = build_action do
        step :a
        step :b
        define_method(:a) { succeed('first') }
        define_method(:b) { nil }
        private :a, :b
      end
      action.run
      expect(log.map { |entry| entry[2] }).to eq([action, action])
      expect(log[0][3]).to be_nil
      expect(log[1][3]).to be_a(Actionable::Success)
    end

    it 'AC-B#recordseam: a halting step still had its call opened, and later steps get none' do
      Thread.current[:record_log] = []
      action = build_action do
        step :a
        step :b
        define_method(:a) { fail!(:stop) }
        define_method(:b) { nil }
        private :a, :b
      end
      action.run
      expect(log.map { |entry| entry[1].name }).to eq(%i[a])
    end

    it 'AC-B#recordreturn: record yields exactly once and returns the block value (default body)' do
      runner = Actionable::Runner.new(build_action.new)
      count = 0
      value = runner.__send__(:record, :main, Actionable::Steps::Method.new(:x)) do
        count += 1
        :from_block
      end
      expect([count, value]).to eq([1, :from_block])
    end

    it 'AC-B#recordseam: record is private' do
      expect(Actionable::Runner.private_instance_methods).to include(:record)
    end
  end

  describe 'step objects' do
    it 'AC-B#stepshapes: method steps have a Symbol name and kind :method' do
      step = build_action { step 'sail' }.steps.first
      expect([step.name, step.kind]).to eq(%i[sail method])
      expect(step).to be_a(Actionable::Steps::Method)
    end

    it 'AC-B#stepshapes: Steps::Base is abstract' do
      base = Actionable::Steps::Base.new(:x)
      expect(base.kind).to eq(:step)
      expect { base.call(Object.new) }.to raise_error(NotImplementedError)
    end

    it 'AC-B#guards: step options are frozen deeply, so the guard snapshot cannot diverge' do
      action = build_action do
        step :a, if: :ready
      end
      step = action.steps.first
      expect { step.options[:unless] = :never }.to raise_error(FrozenError)
      expect { step.options.delete(:if) }.to raise_error(FrozenError)
      child = Class.new(Actionable::Action)
      fields = %i[n]
      action_step = Actionable::Steps.build(child, input: fields, expose: %w[total])
      expect { action_step.options[:input] << :m }.to raise_error(FrozenError)
      expect { action_step.options[:expose] << 'm' }.to raise_error(FrozenError)
      expect(fields).not_to be_frozen
    end

    it 'AC-B#nestedabsorb: a frozen action step that never ran still runs, threading input and expose' do
      kiln = build_action do
        def initialize(clay: 0) = @clay = clay
        step :fire
        def fire = succeed(glaze: @clay * 3, ash: 1)
      end
      frozen = Actionable::Steps.build(kiln, input: %w[clay], expose: %i[glaze]).freeze
      potter = build_action do
        def initialize(clay:) = @clay = clay
        step :tally
        def tally = succeed(glaze: @glaze, ash: @ash)
      end
      potter.steps.replace([frozen, *potter.steps])
      result = potter.run(clay: 4)
      expect(result).to be_success
      expect(result.output).to eq(glaze: 12, ash: nil)
    end

    it 'AC-B#stepdecl: Steps.build rejects non-targets with the documented message' do
      expect { Actionable::Steps.build(3) }.to raise_error(ArgumentError, 'unsupported step target: 3')
    end
  end

  describe 'anonymous classes' do
    it 'AC-B#anonlabel: anonymous actions have a nil name; the base class has its own' do
      expect(build_action.name).to be_nil
      expect(Actionable::Action.name).to eq('Actionable::Action')
    end
  end

  describe 'run_each and BatchResult' do
    let(:action) do
      build_action do
        define_method(:initialize) do |n: 0, extra: nil|
          @n = n
          @extra = extra
        end
        step :sail
        define_method(:sail) do
          if @n.negative?
            fail!(:neg)
          else
            (@n.zero? ? skip!(:zero) : succeed(n: @n))
          end
        end
        private :sail
      end
    end

    it 'AC-B#runeach: runs per item in order, independently, mapping items to args' do
      batch = action.run_each([{ n: 1 }, { n: -1 }, { n: 0 }, { n: 2 }])
      expect(batch).to be_a(Actionable::BatchResult)
      expect(batch.map(&:status)).to eq(%i[success failure skipped success])
    end

    it 'AC-B#runeach: the block maps items; Arrays become positional arguments' do
      positional = build_action do
        define_method(:initialize) { |a, b| @sum = a + b }
        step :sail
        define_method(:sail) { succeed(sum: @sum) }
        private :sail
      end
      batch = positional.run_each([[1, 2], [3, 4]])
      expect(batch.map { |r| r.output[:sum] }).to eq([3, 7])
      mapped = action.run_each(1..2) { |i| { n: i * 10 } }
      expect(mapped.map { |r| r.output[:n] }).to eq([10, 20])
      single = build_action { define_method(:initialize) { |x| @x = x } }
      expect(single.run_each([5, 6]).size).to eq(2)
    end

    it 'AC-B#batchapi: collection helpers' do
      batch = action.run_each([{ n: 1 }, { n: -1 }, { n: 0 }])
      expect(batch.size).to eq(3)
      expect(batch.length).to eq(3)
      expect(batch[0]).to be_success
      expect(batch[9]).to be_nil
      expect(batch).not_to be_empty
      expect(batch.each).to be_a(Enumerator)
      expect(batch.results.size).to eq(3)
      expect(batch.successes.size).to eq(1)
      expect(batch.failures.size).to eq(1)
      expect(batch.skips.size).to eq(1)
      expect(batch).not_to be_all_ok
      expect(batch).to be_any_failure
      expect(batch).to be_partial
    end

    it 'AC-B#batchapi: all_ok?, any_failure? and partial? on edge cases' do
      empty = action.run_each([])
      expect([empty.empty?, empty.all_ok?, empty.any_failure?, empty.partial?]).to eq([true, true, false, false])
      all_failed = action.run_each([{ n: -1 }, { n: -2 }])
      expect([all_failed.all_ok?, all_failed.any_failure?, all_failed.partial?]).to eq([false, true, false])
      expect(action.run_each([{ n: 0 }, { n: 1 }])).to be_all_ok
    end

    it 'AC-B#batchapi: to_api_h maps each result with its index' do
      batch = action.run_each([{ n: 1 }, { n: -1 }])
      expect(batch.to_api_h).to eq([
                                     { index: 0, status: :success, id: nil, errors: {} },
                                     { index: 1, status: :failure, id: nil, errors: {} }
                                   ])
    end
  end
end
