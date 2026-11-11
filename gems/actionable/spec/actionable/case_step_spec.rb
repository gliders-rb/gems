# frozen_string_literal: true

module CaseSpy
  private

  def record(section, step, &block)
    Thread.current[:case_log]&.push([section, step.name, step.kind])
    super
  end
end

RSpec.describe 'Case steps' do
  def kind_action(&)
    build_action do
      attr_reader :log

      define_method(:initialize) { |kind: nil| @kind = kind }
      class_eval(&)
      %i[pick_a pick_bc pick_z pick_default].each do |name|
        define_method(name) { succeed(name.to_s) }
        private name
      end
      private

      attr_reader :kind
    end
  end

  let(:action) do
    kind_action do
      case_step :kind do
        on 'a', :pick_a
        on %w[b c], :pick_bc
        on(/\Az/, :pick_z)
        default :pick_default
      end
    end
  end

  it 'AC-B#casestep: runs the first matching branch (private methods allowed)' do
    expect(action.run(kind: 'a').message).to eq('pick_a')
    expect(action.run(kind: 'c').message).to eq('pick_bc')
    expect(action.run(kind: 'zebra').message).to eq('pick_z')
  end

  it 'AC-B#casestep: falls to the default' do
    expect(action.run(kind: 'q').message).to eq('pick_default')
  end

  it 'AC-B#casenomatch: no match and no default is a no-op' do
    no_default = kind_action { case_step(:kind) { on 'a', :pick_a } }
    result = no_default.run(kind: 'q')
    expect(result).to be_success
    expect(result.message).to be_nil
  end

  it 'AC-B#valuematch: a Range branch never matches a member' do
    ranged = kind_action do
      case_step :kind do
        on 4..6, :pick_a
        default :pick_default
      end
    end
    expect(ranged.run(kind: 5).message).to eq('pick_default')
  end

  it 'AC-B#caseguard: the branch is chosen by value, then its guard decides; no fall-through' do
    guarded = kind_action do
      case_step :kind do
        on 'a', :pick_a, if: :never
        on 'a', :pick_bc
        default :pick_default
      end
      define_method(:never) { false }
    end
    result = guarded.run(kind: 'a')
    expect(result.message).to be_nil
  end

  it 'AC-B#caseguard: the default takes a guard and the case step takes its own' do
    guarded = kind_action do
      case_step(:kind) { default :pick_default, unless: :yes }
      define_method(:yes) { true }
    end
    expect(guarded.run(kind: 'x').message).to be_nil
    whole = kind_action do
      case_step :kind, if: :adrift do
        on 'a', :pick_a
      end
      define_method(:adrift) { false }
    end
    expect(whole.run(kind: 'a').message).to be_nil
  end

  it 'AC-B#casekind: kind is :case and the name is the value-source method' do
    step = action.steps.first
    expect([step.kind, step.name]).to eq(%i[case kind])
    expect(step).to be_a(Actionable::Steps::Case)
    expect(step.branches.size).to eq(3)
    expect(step.default_step.name).to eq(:pick_default)
  end

  it 'AC-B#redeclare: a case step is replaced in place and differs from a method step of the same name' do
    redeclared = build_action do
      case_step(:kind) { on 'a', :one }
      step :other
      case_step(:kind) { on 'b', :two }
      step :kind
    end
    expect(redeclared.steps.map { |s| [s.kind, s.name] }).to eq([%i[case kind], %i[method other], %i[method kind]])
    expect(redeclared.steps.first.branches.map(&:first)).to eq(['b'])
  end

  it 'AC-B#caserequired: the value source and every target must be implemented' do
    broken = build_action do
      case_step :where do
        on 'a', :one
        default :two
      end
    end
    expect { broken.run }.to raise_error(Actionable::DefinitionError, /calling :where, :one, :two but does not/)
  end

  it 'AC-B#casestep: targets may be nested action classes' do
    named_action('CaseChild') do
      step :sail

      private

      def sail = succeed(line: 7)
    end
    parent = kind_action do
      case_step(:kind) { on 'a', CaseChild, expose: %i[line] }
    end
    expect(parent.run(kind: 'a')).to be_success
  end

  describe 'the record seam' do
    before { Actionable::Runner.prepend(CaseSpy) }

    after { Thread.current[:case_log] = nil }

    it 'AC-B#recordseam: a case step is one record call; the branch runs inside it' do
      Thread.current[:case_log] = []
      action.run(kind: 'a')
      expect(Thread.current[:case_log]).to eq([%i[main kind case]])
    end
  end
end
