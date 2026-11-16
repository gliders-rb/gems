# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'describe entry shapes' do
  # A guard object with its own words, as a renderer would want them.
  let(:frost_check) do
    Class.new do
      def call(_action) = false
      def desc = 'a frost is forecast'
    end.new
  end

  let(:allotment) do
    stub_const('Allotment', Module.new)
    stub_const('Allotment::Compost', Class.new(Actionable::Action) { step :turn_heap })
    frost = frost_check
    klass = stub_const('Allotment::PlantOut', Class.new(Actionable::Action))
    klass.class_eval do
      step :harden_off, if: :seedlings_ready?, desc: 'Harden the seedlings off'
      step :fleece_beds, unless: frost, desc: 'Cover the beds'
      step :water_in, if: ->(_plot) { true }, unless: 'raining?'
      case_step :crop, desc: 'Pick the bed' do
        on 'leek', :dib_holes, desc: 'Dib deep holes'
        on %w[bean pea], Allotment::Compost, if: :heap_ready?
        on(/squash/, :mound_soil)
      end
      case_step(:season) { on 'spring', :sow_early }
      on_failure :note_losses, if: :losses?, desc: 'Write down what was lost'
      always Allotment::Compost
    end
    klass
  end

  def entry(name, type: :method, **extra)
    { type: type, name: name, options: {}, description: nil }.merge(extra)
  end

  describe 'AC-B#describe: guard labels' do
    it 'names a Symbol guard, a String guard and a described callable; a bare proc is a custom condition' do
      steps = allotment.describe[:steps]
      expect(steps[0][:guard]).to eq(if: 'seedlings_ready?')
      expect(steps[1][:guard]).to eq(unless: 'a frost is forecast')
      expect(steps[2][:guard]).to eq(if: 'a custom condition', unless: 'raining?')
    end

    it 'leaves guard out when there is none' do
      expect(allotment.describe[:steps][4]).not_to have_key(:guard)
    end
  end

  describe 'AC-B#casekind: branches and default' do
    it 'lists one target per branch, the match value as declared, and the default' do
      kase = allotment.describe[:steps][3]
      expect(kase).to include(type: :case, name: :crop, description: 'Pick the bed', default: nil)
      expect(kase[:branches]).to eq([
                                      { on: 'leek', step: entry(:dib_holes, options: {}, description: 'Dib deep holes') },
                                      { on: %w[bean pea], step: entry(Allotment::Compost, type: :action,
                                                                                          options: { if: :heap_ready? },
                                                                                          guard: { if: 'heap_ready?' }) },
                                      { on: /squash/, step: entry(:mound_soil) }
                                    ])
    end

    it 'gives the default its own step entry' do
      klass = Class.new(Actionable::Action) do
        case_step(:soil) do
          on 'clay', :add_grit
          default :rake_level, desc: 'Rake it level'
        end
      end
      expect(klass.describe[:steps].first[:default]).to eq(entry(:rake_level, description: 'Rake it level'))
    end

    it 'leaves branches and default off other steps' do
      expect(allotment.describe[:steps][0].keys).to eq(%i[type name options description guard])
    end
  end

  describe 'AC-B#describe: hooks are step entries' do
    it 'has the same shape as a step, guard included' do
      hooks = allotment.describe[:hooks]
      expect(hooks[:on_failure]).to eq([entry(:note_losses, options: { if: :losses? }, description: 'Write down what was lost',
                                                            guard: { if: 'losses?' })])
      expect(hooks[:always]).to eq([entry(Allotment::Compost, type: :action)])
      expect(hooks[:on_success]).to eq([])
    end

    it 'keeps describe_text listing hook names' do
      expect(allotment.describe_text).to include("  Hooks:\n    on_failure: note_losses\n    always: Allotment::Compost")
    end
  end
end
