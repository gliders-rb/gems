# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'descriptions' do
  def pottery(&block)
    stub_const('Pottery', Module.new)
    klass = stub_const('Pottery::GlazeBatch', Class.new(Actionable::Action))
    klass.class_eval(&block) if block
    klass
  end

  describe 'AC-B#desc: the action' do
    it 'is set with desc and read with either name' do
      klass = pottery { desc 'Mixes and fires one batch of glaze.' }
      expect(klass.desc).to eq('Mixes and fires one batch of glaze.')
      expect(klass.description).to eq('Mixes and fires one batch of glaze.')
    end

    it 'can be set with description' do
      expect(pottery { description 'Fires a test tile.' }.desc).to eq('Fires a test tile.')
    end

    it 'is nil when none is given' do
      expect(pottery.desc).to be_nil
    end

    it 'is given once per class, by either name' do
      twice = lambda do
        pottery do
          desc 'Mixes glaze.'
          description 'Fires glaze.'
        end
      end
      expect(&twice).to raise_error(Actionable::DefinitionError,
                                    'Pottery::GlazeBatch already has a description; give it once, with desc or description')
      expect { pottery { 2.times { desc 'Mixes glaze.' } } }.to raise_error(Actionable::DefinitionError)
    end

    it 'takes a String' do
      expect { pottery { desc :glaze } }
        .to raise_error(ArgumentError, 'Pottery::GlazeBatch: desc takes a String, got Symbol')
    end

    it 'is not inherited, and a subclass may give its own' do
      parent = pottery { desc 'Base for kiln work.' }
      child = Class.new(parent)
      expect(child.desc).to be_nil
      child.desc 'Bisque firing.'
      expect([parent.desc, child.desc]).to eq(['Base for kiln work.', 'Bisque firing.'])
    end
  end

  describe 'AC-B#desc: steps, branches and hooks' do
    it 'is a core option kept in step.options' do
      klass = pottery do
        step :weigh_oxides, desc: 'Weigh the oxides for the recipe'
        case_step :finish, desc: 'Pick the finish' do
          on 'matte', :add_flux, desc: 'Add flux for a matte surface'
          default :add_silica, desc: 'Add silica for gloss'
        end
        on_failure :scrap_batch, desc: 'Scrap the batch'
        always :wash_buckets, desc: 'Wash the buckets'
      end
      expect(klass.steps.first.options).to eq(desc: 'Weigh the oxides for the recipe')
      expect(klass.steps.to_a.last.options).to eq(desc: 'Pick the finish')
      expect(klass.steps.to_a.last.branch_steps.map { |step| step.options[:desc] })
        .to eq(['Add flux for a matte surface', 'Add silica for gloss'])
      expect(klass.failure_hooks.first.options[:desc]).to eq('Scrap the batch')
    end

    it 'takes a String, named by action and step' do
      expect { pottery { step :weigh_oxides, desc: 42 } }
        .to raise_error(ArgumentError, 'Pottery::GlazeBatch#weigh_oxides: desc: takes a String, got Integer')
      expect { pottery { case_step(:finish) { on 'matte', :add_flux, desc: :flux } } }
        .to raise_error(ArgumentError, 'Pottery::GlazeBatch#add_flux: desc: takes a String, got Symbol')
    end
  end

  describe 'AC-B#desc: fails and skips' do
    let(:klass) do
      pottery do
        fails :crazed, 'the glaze crazed', retry: false, desc: 'Fine cracks showed after cooling'
        skips :kiln_full, desc: 'No shelf space left in this firing'
        step :fire

        private

        def fire = fail!(:crazed)
      end
    end

    it 'is pulled out of the metadata' do
      expect(klass.declared_failures).to eq(crazed: { retry: false })
      expect(klass.failure_declarations[:crazed])
        .to eq(message: 'the glaze crazed', metadata: { retry: false }, description: 'Fine cracks showed after cooling')
      expect(klass.skip_declarations[:kiln_full]).to eq(message: nil, metadata: {}, description: 'No shelf space left in this firing')
    end

    it 'never reaches a result' do
      result = klass.run
      expect(result.metadata).to eq(retry: false)
      expect(result.to_h.to_s).not_to include('Fine cracks')
      expect(result.as_json.to_s).not_to include('Fine cracks')
    end

    it 'leaves description out of a declaration that has none' do
      expect(pottery { fails :cracked }.failure_declarations[:cracked]).to eq(message: nil, metadata: {})
    end

    it 'takes a String' do
      expect { pottery { fails :crazed, desc: 3 } }
        .to raise_error(ArgumentError, 'Pottery::GlazeBatch: fails code :crazed desc: takes a String, got Integer')
      expect { pottery { skips :kiln_full, desc: 3 } }
        .to raise_error(ArgumentError, 'Pottery::GlazeBatch: skips code :kiln_full desc: takes a String, got Integer')
    end
  end

  describe 'AC-B#describe: the description keys' do
    it 'has the action description, each step and each code' do
      klass = pottery do
        desc 'Mixes and fires one batch of glaze.'
        fails :crazed, desc: 'Fine cracks showed after cooling'
        skips :kiln_full
        step :weigh_oxides, desc: 'Weigh the oxides', if: :recipe_ready?
        step :sieve
      end
      info = klass.describe
      expect(info[:description]).to eq('Mixes and fires one batch of glaze.')
      expect(info[:steps].first).to eq(type: :method, name: :weigh_oxides, options: { if: :recipe_ready? },
                                       description: 'Weigh the oxides', guard: { if: 'recipe_ready?' })
      expect(info[:steps].last).to include(description: nil, options: {})
      expect(info[:failures][:crazed]).to eq(message: nil, metadata: {}, description: 'Fine cracks showed after cooling')
      expect(info[:skips][:kiln_full]).to eq(message: nil, metadata: {}, description: nil)
    end

    it 'puts description second' do
      expect(pottery.describe.keys.first(2)).to eq(%i[name description])
    end
  end
end
