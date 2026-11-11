# frozen_string_literal: true

require 'rbs'

RSpec.describe Actionable::RBS do
  # Indents every non-blank line by +width+ spaces (a heredoc for a member inside a top-level class).
  def indented(text, width)
    text.gsub(/^(?=.)/, ' ' * width)
  end

  def parses?(text)
    RBS::Parser.parse_signature(text)
    true
  end

  describe 'arguments (AC-B#rbsargs)' do
    it 'AC-B#rbsargs: refuses what is not an Action subclass' do
      [String, Actionable::Action, 3, nil].each do |bad|
        expect { described_class.generate(bad) }
          .to raise_error(ArgumentError, "Actionable::RBS.generate expects an Actionable::Action subclass, got #{bad.inspect}")
      end
    end

    it 'AC-B#rbsargs: refuses an anonymous action' do
      expect { described_class.generate(Class.new(Actionable::Action)) }
        .to raise_error(ArgumentError, 'cannot generate RBS for an anonymous action')
    end
  end

  describe 'ancestors (AC-B#rbsancestors)' do
    it 'AC-B#rbsancestors: declares every named ancestor first, outermost first, then the action' do
      stub_const('Harbor', Module.new)
      stub_const('Harbor::Base', Class.new(Actionable::Action))
      stub_const('Harbor::Weigh', Class.new(Harbor::Base))
      stub_const('Harbor::HullWeigh', Class.new(Harbor::Weigh))

      expect(described_class.generate(Harbor::HullWeigh)).to eq(<<~RBS)
        module Harbor
          class Base < ::Actionable::Action
          end
        end

        module Harbor
          class Weigh < ::Harbor::Base
          end
        end

        module Harbor
          class HullWeigh < ::Harbor::Weigh
            def self.run: (*untyped) -> ::Actionable::Result
          end
        end
      RBS
    end

    it 'AC-B#rbsancestors: skips an anonymous ancestor; the next named one is the superclass' do
      stub_const('Named', Class.new(Actionable::Action))
      anonymous = Class.new(Named)
      stub_const('Leaf', Class.new(anonymous))

      text = described_class.generate(Leaf)
      expect(text).to start_with("class Named < ::Actionable::Action\nend\n\nclass Leaf < ::Named\n")
      expect(text.scan('class Named').size).to eq(1)
    end

    it 'AC-B#rbsancestors: opens a namespace that is a class as class' do
      stub_const('Voyages', Class.new)
      stub_const('Voyages::Place', Class.new(Actionable::Action))

      expect(described_class.generate(Voyages::Place)).to start_with("class Voyages\n  class Place < ::Actionable::Action\n")
    end

    it 'AC-B#rbsancestors: a typed ancestor declares empty Success, Skipped and Failure; its typed child inherits them' do
      stub_const('Typed', Class.new(Actionable::Action) { typed_outcomes })
      stub_const('TypedChild', Class.new(Typed))

      text = described_class.generate(TypedChild)
      expect(text).to start_with(<<~RBS)
        class Typed < ::Actionable::Action
          class Success < ::Actionable::Success
          end

          class Skipped < ::Actionable::Skipped
          end

          class Failure < ::Actionable::Failure
          end
        end

        class TypedChild < ::Typed
      RBS
      expect(text).to include('class Success < ::Typed::Success', 'class Failure < ::Typed::Failure')
    end

    it 'AC-B#rbsancestors: ancestor declarations are the same in every file, so they merge' do
      stub_const('Shared', Class.new(Actionable::Action))
      stub_const('One', Class.new(Shared))
      stub_const('Two', Class.new(Shared))

      first = described_class.generate(One).split("\n\n").first
      second = described_class.generate(Two).split("\n\n").first
      expect(first).to eq(second)
    end
  end

  describe 'run (AC-B#rbsrun)' do
    it 'AC-B#rbsrun: writes keywords from the fixed input, with an overload for a built input' do
      stub_const('Muster', Class.new(Actionable::Action) do
        input do
          required :callsign, :string
          required :plan, :symbol, default: :free
          optional :nickname, :string
        end
      end)

      expect(described_class.generate(Muster)).to include(indented(<<~RBS, 2))
        def self.run: (callsign: ::String, ?plan: ::Symbol, ?nickname: ::String?) -> ::Actionable::Result
                    | (InputSchema input) -> ::Actionable::Result
      RBS
    end

    it 'AC-B#rbsrun: a free-form action takes untyped positionals' do
      stub_const('Free', Class.new(Actionable::Action))
      expect(described_class.generate(Free)).to include('def self.run: (*untyped) -> ::Actionable::Result')
    end

    it 'AC-B#rbsrun: any action with an input_for dispatch takes untyped positionals and has no InputSchema' do
      callsign = Class.new(FieldStruct::Base) { required :mooring, :string }
      stub_const('Dispatching', Class.new(Actionable::Action) do
        input_for(:kind) { on(:callsign, callsign) }
      end)

      text = described_class.generate(Dispatching)
      expect(text).to include('def self.run: (*untyped) -> ::Actionable::Result')
      expect(text).not_to include('InputSchema')
    end

    it 'AC-B#rbsrun: returns Result with an output schema, the typed union under typed outcomes, else the gem Result' do
      stub_const('WithOutput', Class.new(Actionable::Action) { output { required :id, :integer } })
      stub_const('TypedOne', Class.new(Actionable::Action) { typed_outcomes })

      expect(described_class.generate(WithOutput)).to include('def self.run: (*untyped) -> Result')
      expect(described_class.generate(TypedOne)).to include('def self.run: (*untyped) -> (Success | Skipped | Failure)')
    end
  end

  describe 'input (AC-B#rbsinput)' do
    it 'AC-B#rbsinput: declares input and an InputSchema class with a reader and a nil-taking writer per field' do
      stub_const('Muster', Class.new(Actionable::Action) do
        input do
          required :callsign, :string
          optional :age, :integer
        end
      end)

      expect(described_class.generate(Muster)).to include(indented(<<~RBS, 2))
        def input: () -> InputSchema

        class InputSchema < ::FieldStruct::Base
          attr_reader callsign: ::String
          def callsign=: (::String? value) -> ::String?

          attr_reader age: ::Integer?
          def age=: (::Integer? value) -> ::Integer?
        end
      RBS
    end

    it 'AC-B#rbsinput: refuses an InputSchema constant Ruby already resolves, on the class or an ancestor or module' do
      shared = Module.new
      stub_const('Shared', shared)
      stub_const('Base', Class.new(Actionable::Action) { const_set(:InputSchema, Class.new) })
      stub_const('Child', Class.new(Base) { input { required :a, :string } })
      stub_const('Mixed', Class.new(Actionable::Action) do
        include Shared

        input { required :a, :string }
      end)
      shared.const_set(:InputSchema, Class.new)

      expect { described_class.generate(Child) }
        .to raise_error(ArgumentError, 'Child::InputSchema is already defined (in Base); Actionable::RBS.generate names the ' \
                                       'generated input type InputSchema, so rename that constant')
      expect { described_class.generate(Mixed) }
        .to raise_error(ArgumentError, /Mixed::InputSchema is already defined \(in Shared\)/)
    end

    it 'AC-B#rbsinput: a top-level InputSchema constant does not count' do
      stub_const('InputSchema', Class.new)
      stub_const('Fine', Class.new(Actionable::Action) { input { required :a, :string } })
      expect { described_class.generate(Fine) }.not_to raise_error
    end
  end

  describe 'instance variables and result (AC-B#rbsivars)' do
    it 'AC-B#rbsivars: one nullable ivar per output field, then Output and Result' do
      stub_const('Fare', Class.new(Actionable::Action) do
        output do
          required :fare, :integer
          optional :note, :string
        end
      end)

      expect(described_class.generate(Fare)).to eq(<<~RBS)
        class Fare < ::Actionable::Action
          def self.run: (*untyped) -> Result

          @fare: ::Integer?
          @note: ::String?

          class Output < ::FieldStruct::Base
            attr_reader fare: ::Integer
            def fare=: (::Integer? value) -> ::Integer?

            attr_reader note: ::String?
            def note=: (::String? value) -> ::String?
          end

          class Result < ::Actionable::Result
            def output: () -> Output

            def fare: () -> ::Integer
            def note: () -> ::String?
          end
        end
      RBS
    end
  end

  describe 'aliases (AC-B#rbsaliases)' do
    it 'AC-B#rbsaliases: failure_code lists declared codes then the gem codes; skip_code only declared; failures first' do
      stub_const('Coded', Class.new(Actionable::Action) do
        skips :nothing_to_do
        fails :declined
        fails :invalid_input
      end)

      text = described_class.generate(Coded)
      expect(text).to include("type failure_code = :declined | :invalid_input | :invalid_output\n")
      expect(text).to include('type skip_code = :nothing_to_do')
      expect(text.index('type failure_code')).to be < text.index('type skip_code')
    end

    it 'AC-B#rbsaliases: no aliases for an action that declares nothing' do
      stub_const('Quiet', Class.new(Actionable::Action))
      expect(described_class.generate(Quiet)).not_to include('type ')
    end
  end

  describe 'typed outcomes (AC-B#rbstyped)' do
    let(:action) do
      stub_const('Embark', Class.new(Actionable::Action) do
        typed_outcomes
        output do
          required :fare, :integer
          optional :memo, :string
        end
        fails(:deck_full) { required :berth, :string }
        fails :declined?
        skips(:already_paid) { optional :memo, :integer }
        skips :nothing_to_do
      end)
    end

    it 'AC-B#rbstyped: writes Output, then skip outputs, then failure outputs, then the three result classes' do
      text = described_class.generate(action)
      positions = ['class Output ', 'class AlreadyPaidSkipOutput ', 'class DeckFullFailureOutput ', 'class Success ',
                   'class Skipped ', 'class Failure '].map { |needle| text.index(needle) }
      expect(positions).to eq(positions.sort)
      expect(positions).to all(be_a(Integer))
    end

    it 'AC-B#rbstyped: Success carries its code, output and a reader per field' do
      expect(described_class.generate(action)).to include(indented(<<~RBS, 2))
        class Success < ::Actionable::Success
          def code: () -> :success
          def output: () -> Output

          def fare: () -> ::Integer
          def memo: () -> ::String?
        end
      RBS
    end

    it 'AC-B#rbstyped: Skipped has the skip code alias, the union of skip outputs and the Hash, and unioned readers' do
      expect(described_class.generate(action)).to include(indented(<<~RBS, 2))
        class Skipped < ::Actionable::Skipped
          def code: () -> skip_code
          def output: () -> (AlreadyPaidSkipOutput | ::Hash[::Symbol, untyped])

          def memo: () -> ::Integer?
        end
      RBS
    end

    it 'AC-B#rbstyped: Failure has every reader nullable and the union of failure, skip and Output classes and the Hash' do
      expect(described_class.generate(action)).to include(indented(<<~RBS, 2))
        class Failure < ::Actionable::Failure
          def code: () -> failure_code
          def output: () -> (DeckFullFailureOutput | AlreadyPaidSkipOutput | Output | ::Hash[::Symbol, untyped])

          def berth: () -> ::String?
          def memo: () -> (::Integer | ::String)?
          def fare: () -> ::Integer?
        end
      RBS
    end

    it 'AC-B#rbstyped: without declared codes the code types are Symbol and the outputs are Hashes' do
      stub_const('Bare', Class.new(Actionable::Action) { typed_outcomes })
      text = described_class.generate(Bare)
      expect(text).to include('def code: () -> ::Symbol', 'def output: () -> ::Hash[::Symbol, untyped]')
    end

    it 'AC-B#rbstyped: a skip field declared in several schemas is the union, nullable when any is optional' do
      stub_const('Multi', Class.new(Actionable::Action) do
        typed_outcomes
        skips(:a) { required :n, :integer }
        skips(:b) { required :n, :string }
        skips(:c) { optional :n, :integer }
      end)
      expect(described_class.generate(Multi)).to include('def n: () -> (::Integer | ::String)?')
    end

    it 'AC-B#rbstyped: a child of a typed parent inherits the parent own result classes' do
      stub_const('Parent', Class.new(Actionable::Action) { typed_outcomes })
      stub_const('Kid', Class.new(Parent))
      text = described_class.generate(Kid)
      expect(text).to include('class Success < ::Parent::Success', 'class Skipped < ::Parent::Skipped',
                              'class Failure < ::Parent::Failure')
    end

    it 'AC-B#rbstyped: ? and ! in a code become Predicate and Bang in the class name' do
      stub_const('Names', Class.new(Actionable::Action) do
        typed_outcomes
        fails(:expired?) { required :on, :string }
        fails(:weigh!) { required :id, :string }
      end)
      expect(described_class.generate(Names)).to include('class ExpiredPredicateFailureOutput', 'class WeighBangFailureOutput')
    end

    it 'AC-B#rbstyped: two codes of one kind that name the same class are refused, naming both' do
      stub_const('Clash', Class.new(Actionable::Action) do
        typed_outcomes
        fails(:expired?) { required :on, :string }
        fails(:expired_predicate) { required :on, :string }
      end)
      expect { described_class.generate(Clash) }
        .to raise_error(ArgumentError, 'Clash: failure codes :expired? and :expired_predicate both name ExpiredPredicateFailureOutput ' \
                                       'in the generated RBS; rename one of the codes')
    end

    it 'AC-B#rbstyped: a trailing underscore clashes with the plain code' do
      stub_const('Clash2', Class.new(Actionable::Action) do
        typed_outcomes
        skips(:ready) { required :on, :string }
        skips(:ready_) { required :on, :string }
      end)
      expect { described_class.generate(Clash2) }
        .to raise_error(ArgumentError, /Clash2: skip codes :ready and :ready_ both name ReadySkipOutput/)
    end

    it 'AC-B#rbstyped: a code that gives no ASCII-capital class name is refused' do
      stub_const('Accent', Class.new(Actionable::Action) do
        typed_outcomes
        skips(:éclair) { required :on, :string }
      end)
      expect { described_class.generate(Accent) }
        .to raise_error(ArgumentError, 'Accent: skip code :éclair gives éclairSkipOutput, which is not a valid RBS class name ' \
                                       '(it must start with an ASCII capital); rename the code')
    end
  end

  describe 'format (AC-B#rbsformat)' do
    it 'AC-B#rbsformat: indents two spaces per level, keeps blank lines empty, ends with one newline, qualifies types' do
      stub_const('Deep', Module.new)
      stub_const('Deep::Er', Module.new)
      stub_const('Deep::Er::Act', Class.new(Actionable::Action) do
        input { required :n, :integer }
        output { required :m, :integer }
      end)

      text = described_class.generate(Deep::Er::Act)
      expect(text).to end_with("end\n")
      expect(text).not_to end_with("\n\n")
      expect(text.lines.map(&:chomp)).to all(satisfy { |line| line.empty? || !line.match?(/\s\z/) })
      expect(text).to include("module Deep\n  module Er\n    class Act < ::Actionable::Action\n      def self.run:")
      expect(text).to include('::Integer')
      expect(text.lines.map { |line| line[/\A */].size }).to all(satisfy(&:even?))
    end

    it 'AC-B#rbsformat: every generated shape is valid RBS syntax' do
      stub_const('Everything', Class.new(Actionable::Action) do
        typed_outcomes
        input { required :a, :string }
        output { optional :b, :integer }
        fails(:bad) { required :c, :string }
        skips :adrift
      end)
      stub_const('Everything2', Class.new(Actionable::Action) { output { required :z, :integer } })

      expect(parses?(described_class.generate(Everything))).to be(true)
      expect(parses?(described_class.generate(Everything2))).to be(true)
    end
  end
end
