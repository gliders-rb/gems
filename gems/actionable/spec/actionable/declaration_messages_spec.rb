# frozen_string_literal: true

RSpec.describe 'Declaration mistakes fail at load, by name (AC-I8)' do
  describe 'AC-B#declare: a declared code must be an identifier' do
    it 'refuses a number with an ArgumentError that names the action' do
      expect { named_action('Kiln') { fails 5 } }
        .to raise_error(ArgumentError, 'Kiln: fails code 5 is not an identifier; use a Symbol like :out_of_stock')
    end

    it 'refuses nil and a sentence the same way' do
      expect { build_action { fails nil } }.to raise_error(ArgumentError, /\Aaction: fails code nil is not an identifier/)
      expect { build_action { fails 'too hot' } }.to raise_error(ArgumentError, /fails code "too hot" is not an identifier/)
    end

    it 'checks skips with its own wording' do
      expect { named_action('Kiln') { skips 7 } }
        .to raise_error(ArgumentError, 'Kiln: skips code 7 is not an identifier; use a Symbol like :nothing_to_do')
    end

    it 'still takes Symbol and String identifiers' do
      action = build_action do
        fails :cracked
        skips 'cold'
      end
      expect([action.declared_failures.keys, action.declared_skips.keys]).to eq([[:cracked], [:cold]])
    end
  end

  describe 'AC-B#guards: a guard of the wrong type' do
    it 'raises at declaration, naming the action and the step' do
      expect { named_action('Kiln') { step :fire, if: 5 } }
        .to raise_error(ArgumentError, 'Kiln#fire: if: takes a method name (Symbol or String) or a callable, got Integer (5)')
    end

    it 'covers unless: and hooks too' do
      expect { named_action('Kiln') { on_failure :vent, unless: [:hot] } }
        .to raise_error(ArgumentError, /\AKiln#vent: unless: takes a method name .* got Array \(\[:hot\]\)\z/)
    end

    it 'names a child action step by the child' do
      stub_const('Glaze', build_action)
      expect { named_action('Kiln') { step Glaze, if: nil } }
        .to raise_error(ArgumentError, 'Kiln#Glaze: if: takes a method name (Symbol or String) or a callable, got NilClass (nil)')
    end

    it 'accepts Symbols, Strings and callables' do
      action = build_action do
        step :fire, if: :ready?
        step :cool, unless: 'hot?'
        always :log, if: proc { true }
        def fire = nil
        def cool = nil
        def log = nil
        def ready? = true
        def hot? = false
      end
      expect(action.run).to be_success
    end
  end

  describe 'AC-B#missingmethod: the message names each kind' do
    it 'says hook(s) for a missing hook method' do
      action = named_action('Kiln') do
        step :fire
        on_success :vent
        def fire = nil
      end
      expect { action.run }
        .to raise_error(Actionable::DefinitionError, 'Kiln declares hook(s) calling :vent but does not implement them')
    end

    it 'lists steps before hooks, joined by and' do
      action = named_action('Kiln') do
        step :fire
        step :cool
        always :log
      end
      expect { action.run }.to raise_error(Actionable::DefinitionError,
                                           'Kiln declares step(s) calling :fire, :cool and hook(s) calling :log ' \
                                           'but does not implement them')
    end
  end
end
