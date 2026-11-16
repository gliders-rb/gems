# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'step option keys' do
  # Registered keys are process-wide; each example removes what it added.
  around do |example|
    before = Actionable.registered_step_options.keys
    example.run
  ensure
    added = Actionable.registered_step_options.keys - before
    added.each { |key| Actionable.instance_variable_get(:@step_options).delete(key) }
  end

  def glassworks(&block)
    stub_const('Glassworks', Module.new)
    klass = stub_const('Glassworks::Anneal', Class.new(Actionable::Action))
    klass.class_eval(&block)
    klass
  end

  describe 'AC-B#stepoptions' do
    it 'refuses a misspelled key at load, naming the action and the step, with a did-you-mean' do
      expect { glassworks { step :gather_melt, iff: -> { false } } }
        .to raise_error(Actionable::DefinitionError,
                        'unknown step option iff: on Glassworks::Anneal#gather_melt (did you mean if:?)')
    end

    it 'lists the known keys when nothing is close' do
      expect { glassworks { step :gather_melt, kiln_colour: 'amber' } }
        .to raise_error(Actionable::DefinitionError,
                        'unknown step option kiln_colour: on Glassworks::Anneal#gather_melt ' \
                        '(known: desc:, expose:, if:, input:, unless:)')
    end

    it 'accepts the core keys on every kind of step' do
      stub_const('Blowpipe', Class.new(Actionable::Action) { step :blow })
      klass = glassworks do
        step :gather_melt, if: :hot?, unless: :cracked?
        step Blowpipe, input: %i[gob], expose: %i[vessel]
        on_success :stamp, input: %i[gob]
      end
      expect(klass.steps.size).to eq(2)
    end

    it 'checks hooks, with the hook target as the label' do
      expect { glassworks { always :sweep_bench, unles: :tidy? } }
        .to raise_error(Actionable::DefinitionError,
                        /\Aunknown step option unles: on Glassworks::Anneal#sweep_bench \(did you mean unless:\?\)\z/)
    end

    it 'checks a case step and each of its branches when the case step is declared' do
      expect do
        glassworks do
          case_step :colour do
            on 'cobalt', :tint_blue, expsoe: %i[shade]
          end
        end
      end.to raise_error(Actionable::DefinitionError,
                         /unknown step option expsoe: on Glassworks::Anneal#tint_blue \(did you mean expose:\?\)/)
      expect { glassworks { case_step(:colour, iff: :ready?) { default :tint_clear } } }
        .to raise_error(Actionable::DefinitionError, /unknown step option iff: on Glassworks::Anneal#colour/)
    end

    it 'checks the guard type of a branch at declaration too (AC-B#guards)' do
      expect { glassworks { case_step(:colour) { default :tint_clear, if: 7 } } }
        .to raise_error(ArgumentError, 'Glassworks::Anneal#tint_clear: if: takes a method name (Symbol or String) or a ' \
                                       'callable, got Integer (7)')
    end

    it 'accepts a registered key and keeps it in step.options' do
      Actionable.register_step_option(:kiln_temp, owner: 'glass-kiln')
      klass = glassworks { step :gather_melt, kiln_temp: 540 }
      expect(klass.steps.first.options).to eq(kiln_temp: 540)
    end

    it 'suggests a registered key too' do
      Actionable.register_step_option(:kiln_temp, owner: 'glass-kiln')
      expect { glassworks { step :gather_melt, kiln_tmp: 540 } }
        .to raise_error(Actionable::DefinitionError, /\(did you mean kiln_temp:\?\)\z/)
    end
  end

  describe 'AC-B#registerstep' do
    it 'returns the name as a Symbol and lists it with its owner' do
      expect(Actionable.register_step_option('punty', owner: 'glass-rod')).to eq(:punty)
      expect(Actionable.registered_step_options).to include(punty: 'glass-rod')
      expect(Actionable.registered_step_options).to be_frozen
    end

    it 'is a no-op the second time with the same owner' do
      Actionable.register_step_option(:punty, owner: 'glass-rod')
      expect { Actionable.register_step_option(:punty, owner: 'glass-rod') }.not_to raise_error
      expect(Actionable.registered_step_options.keys.count(:punty)).to eq(1)
    end

    it 'refuses the same name under another owner' do
      Actionable.register_step_option(:punty, owner: 'glass-rod')
      expect { Actionable.register_step_option(:punty, owner: 'marver-tools') }
        .to raise_error(ArgumentError, 'step option punty: is already registered by glass-rod')
    end

    it 'refuses a core key' do
      expect { Actionable.register_step_option(:if, owner: 'glass-rod') }
        .to raise_error(ArgumentError, "step option if: is built into actionable-rb and can't be registered")
    end

    it 'needs an owner' do
      message = 'register_step_option needs owner: a non-empty String naming the gem or app that reads the key'
      expect { Actionable.register_step_option(:punty, owner: '') }.to raise_error(ArgumentError, message)
      expect { Actionable.register_step_option(:punty, owner: :glass) }.to raise_error(ArgumentError, message)
    end

    it 'leaves core keys out of the registered list' do
      expect(Actionable.registered_step_options.keys).not_to include(:if, :unless, :input, :expose, :desc)
    end
  end
end
