# frozen_string_literal: true

RSpec.describe 'Action guardrails' do
  describe 'missing methods' do
    it 'AC-B#missingmethod: lists every unimplemented step before running anything' do
      ran = []
      named_action('Incomplete') do
        step :first
        step :second
        step :third
        define_method(:first) { ran << :first }
      end
      expect { Incomplete.run }.to raise_error(Actionable::DefinitionError,
                                               'Incomplete declares step(s) calling :second, :third but does not implement them')
      expect(ran).to be_empty
    end

    it 'AC-B#missingmethod: private methods count; Kernel and Object methods do not' do
      ok = build_action do
        step :secret
        private

        def secret = nil
      end
      expect(ok.run).to be_success
      %i[puts exit object_id].each do |name|
        action = build_action { step name }
        expect do
          action.run
        end.to raise_error(Actionable::DefinitionError, /declares step\(s\) calling #{name.inspect} but does not implement/)
      end
    end

    it 'AC-B#missingmethod: steps whose guard would skip them are still checked; anonymous classes say action' do
      action = build_action { step :nowhere, if: -> { false } }
      expect do
        action.run
      end.to raise_error(Actionable::DefinitionError, 'action declares step(s) calling :nowhere but does not implement them')
    end

    it 'AC-B#missingmethod: a passing check is remembered, and redone when methods or steps change' do
      action = build_action do
        step :one
        def one = nil
      end
      expect(action.run).to be_success
      action.step :two
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :two but/)
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :two but/)
      action.define_method(:two) { nil }
      expect(action.run).to be_success
      action.send(:remove_method, :two)
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :two but/)
      action.define_method(:two) { nil }
      expect(action.run).to be_success
    end

    it 'AC-B#missingmethod: a method added to a parent after the child ran is seen by the child' do
      parent = build_action
      child = Class.new(parent) { step :late }
      expect { child.run }.to raise_error(Actionable::DefinitionError, /calling :late but/)
      parent.define_method(:late) { nil }
      expect(child.run).to be_success
    end

    it 'AC-B#missingmethod: a method removed or undefined on an included module is seen after a pass' do
      mod = Module.new { def polish = nil }
      action = build_action do
        include mod

        step :polish
      end
      expect(action.run).to be_success
      mod.send(:remove_method, :polish)
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :polish but/)
      mod.send(:define_method, :polish) { nil }
      expect(action.run).to be_success
      mod.send(:undef_method, :polish)
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :polish but/)
    end

    it 'AC-B#missingmethod: per-instance methods (singleton, extend) are judged per instance' do
      helper = Module.new { def work = nil }
      action = build_action do
        step :work
        define_method(:initialize) do |mode = :none|
          case mode
          when :singleton then define_singleton_method(:work) { nil }
          when :extend then extend(helper)
          end
        end
      end
      expect(action.run(:singleton)).to be_success
      expect { action.run(:none) }.to raise_error(Actionable::DefinitionError, /calling :work but/)
      expect(action.run(:extend)).to be_success
      expect { action.run(:none) }.to raise_error(Actionable::DefinitionError, /calling :work but/)
    end

    it 'AC-B#missingmethod: a user method_removed that skips super does not hide a removal' do
      action = build_action do
        def self.method_removed(_name); end
        step :gone
        def gone = nil
      end
      expect(action.run).to be_success
      action.send(:remove_method, :gone)
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :gone but/)
    end

    it 'AC-B#missingmethod: a step added straight to the step set is checked' do
      action = build_action do
        step :ok
        def ok = nil
      end
      expect(action.run).to be_success
      action.steps << Actionable::Steps.build(:stow)
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :stow but/)
    end

    it 'AC-B#missingmethod: a step swapped in directly, leaving every set the same size, is checked' do
      action = build_action do
        step :rinse
        on_success :dry
        def rinse = nil
        def dry = nil
      end
      expect(action.run).to be_success
      action.success_hooks.delete(action.success_hooks.first)
      action.success_hooks << Actionable::Steps.build(:fold)
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :fold but/)
      action.steps.clear
      action.steps.merge([Actionable::Steps.build(:press)])
      expect { action.run }.to raise_error(Actionable::DefinitionError, /calling :press, :fold but/)
    end

    it 'AC-B#runorder: input is validated before the method check' do
      action = build_action do
        input { required :n, :integer }
        step :nowhere
      end
      expect(action.run.code).to eq(:invalid_input)
      expect { action.run(n: 1) }.to raise_error(Actionable::DefinitionError)
    end
  end

  describe 'measure' do
    it 'AC-B#measurevalidate: defaults to :none and returns the resolved mode' do
      action = build_action
      expect(action.measure).to eq(:none)
      expect(action.measure(:all)).to eq(:all)
      expect(action.measure).to eq(:all)
      expect(action).to be_measure_all
      expect(action.measure_rate).to be_nil
    end

    it 'AC-B#measurevalidate: refuses unknown modes and bad rates' do
      action = build_action
      expect { action.measure(:bogus) }.to raise_error(ArgumentError, 'unknown measure mode :bogus')
      expect { action.measure(:sampled) }.to raise_error(ArgumentError, 'measure :sampled requires rate: between 0 and 1, got nil')
      expect { action.measure(:sampled, rate: 2) }.to raise_error(ArgumentError, 'measure :sampled requires rate: between 0 and 1, got 2')
      expect { action.measure(:sampled, rate: 'x') }.to raise_error(ArgumentError, /got "x"/)
    end

    it 'AC-B#sampling: rate 1 always hits, rate 0 never; the stored rate is readable' do
      always = build_action { measure :sampled, rate: 1 }
      never = build_action { measure :sampled, rate: 0.0 }
      expect(always.measure_rate).to eq(1)
      expect(always).to be_measure_sampled
      expect(Array.new(20) { always.measure_sample_hit? }).to all(be(true))
      expect(Array.new(20) { never.measure_sample_hit? }).to all(be(false))
      expect(build_action.measure_sample_hit?).to be(false)
    end

    it 'AC-B#measureinherit: mode and rate are inherited by snapshot' do
      parent = build_action { measure :sampled, rate: 0.5 }
      child = build_action(parent)
      parent.measure(:all)
      expect([child.measure, child.measure_rate]).to eq([:sampled, 0.5])
      child.measure(:none)
      expect(parent.measure).to eq(:all)
    end
  end
end
