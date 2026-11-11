# frozen_string_literal: true

require_relative 'coverage_helper'

RSpec.describe Actionable::Coverage do
  describe 'AC-B#covoutcomes' do
    it 'always expects success, then each declared failure and skip' do
      klass = cov_action('OutA', fails: %i[a b], skips: [:c])
      expect(described_class.expected_outcomes(klass)).to eq(%w[success failure:a failure:b skipped:c])
    end

    it 'adds nothing for gem codes unless configured' do
      klass = cov_action('OutB') { input { required :n, :integer } }
      expect(described_class.expected_outcomes(klass)).to eq(['success'])
    end

    context 'with gem codes configured' do
      before { described_class.gem_codes = %i[invalid_input invalid_output] }

      it 'expects invalid_input for a fixed input with a required field' do
        klass = cov_action('OutC') { input { required :n, :integer } }
        expect(described_class.expected_outcomes(klass)).to include('failure:invalid_input')
      end

      it 'does not for an all-optional input or no input' do
        all_optional = cov_action('OutD') { input { optional :n, :integer } }
        expect(described_class.expected_outcomes(all_optional)).to eq(['success'])
        expect(described_class.expected_outcomes(cov_action('OutE'))).to eq(['success'])
      end

      it 'expects it for a dispatch without a default, or with any required reachable schema' do
        a = Class.new(FieldStruct::Base) { optional :x, :string }
        b = Class.new(FieldStruct::Base) { required :y, :string }
        no_default = cov_action('OutF') { input_for(:kind) { on 'a', a } }
        optional_default = cov_action('OutG') do
          input_for(:kind) do
            on 'a', a
            default a
          end
        end
        required_branch = cov_action('OutH') do
          input_for(:kind) do
            on 'b', b
            default a
          end
        end
        expect(described_class.expected_outcomes(no_default)).to include('failure:invalid_input')
        expect(described_class.expected_outcomes(optional_default)).not_to include('failure:invalid_input')
        expect(described_class.expected_outcomes(required_branch)).to include('failure:invalid_input')
      end

      it 'expects invalid_output when any schema a run can be held to has a required field' do
        success = cov_action('OutI') { output { required :id, :integer } }
        coded = cov_action('OutJ') do
          fails(:x) { required :why, :string }
          output { optional :id, :integer }
        end
        none = cov_action('OutK') { output { optional :id, :integer } }
        expect(described_class.expected_outcomes(success)).to include('failure:invalid_output')
        expect(described_class.expected_outcomes(coded)).to include('failure:invalid_output')
        expect(described_class.expected_outcomes(none)).not_to include('failure:invalid_output')
      end

      it 'does not list a gem code twice when also declared' do
        klass = cov_action('OutL', fails: [:invalid_input]) { input { required :n, :integer } }
        expect(described_class.expected_outcomes(klass).count('failure:invalid_input')).to eq(1)
      end
    end
  end

  describe 'AC-B#covactions' do
    it 'lists named descendants of root with steps, sorted by name' do
      cov_action('ActZ')
      cov_action('ActA')
      stub_const('ActAbstract', Class.new(Actionable::Action))
      expect(described_class.actions.map(&:name)).to eq(%w[ActA ActZ])
    end

    it 'finds nested and Foo = Class.new(Action) style names, skips anonymous ones' do
      base = cov_action('ActBase')
      cov_action('ActChild', parent: base)
      stub_const('ActAssigned', Class.new(Actionable::Action) { step(:sail) && nil }.tap { |k| k.define_method(:sail) { nil } })
      build_action { step(:sail) }
      expect(described_class.actions.map(&:name)).to eq(%w[ActAssigned ActBase ActChild])
    end

    it 'drops a class whose name no longer resolves to it' do
      klass = cov_action('ActMoved')
      stub_const('ActMoved', Class.new)
      expect(described_class.actions).not_to include(klass)
    end

    it 'runs the loader first' do
      loaded = false
      described_class.loader = -> { (loaded = true) && cov_action('ActLoaded') }
      expect(described_class.actions.map(&:name)).to include('ActLoaded')
      expect(loaded).to be(true)
    end

    it 'applies prefix and Regexp filters, include restricting' do
      %w[App::One App::Two Lib::Three].each { |n| stub_const(n, Class.new(Actionable::Action) { step(:sail) && nil }.tap { |k| k.define_method(:sail) { nil } }) }
      described_class.include_prefixes = ['App::']
      expect(described_class.actions.map(&:name)).to eq(%w[App::One App::Two])
      described_class.exclude_prefixes = [/Two\z/]
      expect(described_class.actions.map(&:name)).to eq(%w[App::One])
      described_class.include_prefixes = [/Three/]
      expect(described_class.actions.map(&:name)).to eq(%w[Lib::Three])
      described_class.exclude_prefixes = ['Lib::']
      expect(described_class.actions).to be_empty
    end

    it 'honours a custom root' do
      base = cov_action('RootBase')
      cov_action('RootKid', parent: base)
      described_class.root = base
      expect(described_class.actions.map(&:name)).to eq(%w[RootKid])
    end
  end
end
