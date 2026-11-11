# frozen_string_literal: true

RSpec.describe 'Typed outcomes' do
  # A one-step action whose step runs +body+; +setup+ is class-level declarations.
  def action_with(parent = Actionable::Action, setup: nil, &body)
    build_action(parent) do
      class_exec(&setup) if setup
      step :sail
      define_method(:sail, &body)
      private :sail
    end
  end

  describe 'the flag (AC-B#typedflag)' do
    it 'defaults off, turns on and off, and returns the new setting' do
      action = build_action
      expect(action.typed_outcomes?).to be(false)
      expect(action.typed_outcomes).to be(true)
      expect(action.typed_outcomes?).to be(true)
      expect(action.typed_outcomes(enabled: false)).to be(false)
      expect(action.typed_outcomes?).to be(false)
    end

    it 'is inherited by snapshot and a subclass can turn it off for itself' do
      parent = build_action { typed_outcomes }
      child = Class.new(parent)
      off = Class.new(parent) { typed_outcomes enabled: false }
      expect([child.typed_outcomes?, off.typed_outcomes?]).to eq([true, false])
      later = build_action
      sub = Class.new(later)
      later.typed_outcomes
      expect(sub.typed_outcomes?).to be(false)
    end
  end

  describe 'result classes (AC-B#resultclasses)' do
    it 'defines Success, Failure and Skipped inside the action, subclassing the gem classes' do
      action = named_action('Typed::Probe') { typed_outcomes }
      expect(action::Success.superclass).to eq(Actionable::Success)
      expect(action::Failure.superclass).to eq(Actionable::Failure)
      expect(action::Skipped.superclass).to eq(Actionable::Skipped)
    end

    it 'returns instances of the action own classes, which are still gem results' do
      action = action_with(setup: lambda {
        typed_outcomes
        fails(:adrift)
        skips(:later)
      }) do
        case @mode
        when :fail then fail!(:adrift)
        when :skip then skip!(:later)
        end
      end
      action.send(:define_method, :initialize) { |mode: nil| @mode = mode }
      ok = action.run
      bad = action.run(mode: :fail)
      skipped = action.run(mode: :skip)
      expect(ok).to be_instance_of(action::Success)
      expect(bad).to be_instance_of(action::Failure)
      expect(skipped).to be_instance_of(action::Skipped)
      expect([ok, bad, skipped]).to all(be_a(Actionable::Result))
      expect(bad).to be_a(Actionable::Failure)
    end

    it 'a subclass of a typed action subclasses the parent own classes, also when it inherits the flag' do
      parent = named_action('Typed::Base') { typed_outcomes }
      child = Class.new(parent)
      expect(child::Failure.superclass).to eq(parent::Failure)
      expect(child::Success.superclass).to eq(parent::Success)
      turned_on = Class.new(parent) { typed_outcomes enabled: false }
      expect(turned_on.run).to be_instance_of(Actionable::Success)
      grandchild = Class.new(turned_on) { typed_outcomes }
      expect(grandchild::Skipped.superclass).to eq(Actionable::Skipped)
    end

    it 'refuses to replace a constant the action already has' do
      %i[Success Failure Skipped].each do |const|
        action = build_action { const_set(const, Class.new) }
        expect { action.typed_outcomes }
          .to raise_error(Actionable::DefinitionError, "action has its own #{const}, which typed outcomes would replace; rename it")
      end
      named = named_action('Typed::Clash') { const_set(:Failure, Class.new) }
      expect { named.typed_outcomes }
        .to raise_error(Actionable::DefinitionError, 'Typed::Clash has its own Failure, which typed outcomes would replace; rename it')
    end

    it 'turning it on twice is harmless' do
      action = build_action { typed_outcomes }
      expect { action.typed_outcomes }.not_to raise_error
    end

    it 'rebuilds a gem result with the same attributes, output_fields_set and exactly the same errors' do
      action = build_action do
        typed_outcomes
        input { required :n, :integer }
        output { required :fare, :integer }
        step :sail
        define_method(:sail) { @fare = 1 }
      end
      invalid = action.run
      expect(invalid).to be_instance_of(action::Failure)
      expect(invalid.code).to eq(:invalid_input)
      expect(invalid.errors.to_h).to eq(n: ['is required'])
      ok = action.run(n: 1)
      expect(ok).to be_instance_of(action::Success)
      expect(ok.output_fields_set).to eq([:fare])
      expect(ok.fare).to eq(1)
    end

    it 'keeps the invalid output struct and field errors of invalid_output, with no output error' do
      action = build_action do
        typed_outcomes
        output { required :fare, :integer }
        step :sail
        define_method(:sail) { nil }
      end
      result = action.run
      expect(result).to be_instance_of(action::Failure)
      expect(result.code).to eq(:invalid_output)
      expect(result.errors.to_h).to eq(fare: ['is required'])
      expect(result.output.valid?).to be(false)
    end

    it 'returns a host own result subclass untouched' do
      host = Class.new(Actionable::Failure)
      action = build_action do
        typed_outcomes
        step :sail
        define_method(:sail) do
          @result = host.new(code: :custom)
          halt!
        end
      end
      expect(action.run).to be_instance_of(host)
    end

    it 'rebuilds another action own result (a crossed failure) as its own class' do
      other = build_action do
        typed_outcomes
        fails(:x)
        step :sail
        define_method(:sail) { fail!(:x) }
      end
      mine = build_action do
        typed_outcomes
        fails(:x)
        step :sail
        define_method(:sail) do
          @result = other.run
          halt!
        end
      end
      result = mine.run
      expect(result).to be_instance_of(mine::Failure)
      expect(result.code).to eq(:x)
    end

    it 'AC-B#typedequality: compares by class, so only the action own class is equal' do
      action = build_action { typed_outcomes }
      result = action.run
      expect(result).not_to eq(Actionable::Success.new)
      expect(result).to eq(action::Success.new)
    end

    it 'leaves untyped actions returning the gem classes' do
      expect(build_action.run).to be_instance_of(Actionable::Success)
    end
  end

  describe 'per-code schemas (AC-B#typedschema)' do
    let(:action) do
      klass = action_with(setup: lambda {
        fails(:rejected, 'no') do
          required :detail, :string
          optional :count, :integer
        end
        skips(:duplicate) { required :note, :string }
      }) do
        @note = 'from ivar'
        case @mode
        when :fail then fail!(:rejected, output: { detail: 'why', count: '3', extra: 1 })
        when :fail_bad then fail!(:rejected, output: { count: 1 })
        when :fail_struct then fail!(:rejected, output: self.class.failure_output_schema(:rejected).new(detail: 'st'))
        when :skip then skip!(:duplicate, note: 'seen')
        when :skip_ivar then skip!(:duplicate)
        end
      end
      klass.send(:define_method, :initialize) { |mode: nil| @mode = mode }
      klass
    end

    it 'builds a failure output from the output: keyword, coerced, with undeclared keys dropped' do
      result = action.run(mode: :fail)
      expect(result.code).to eq(:rejected)
      expect(result.message).to eq('no')
      expect(result.output).to be_a(action.failure_output_schema(:rejected))
      expect([result.output.detail, result.output.count]).to eq(['why', 3])
      expect(result.detail).to eq('why')
      expect(result.output_fields_set).to eq(%i[detail count])
      expect(result.errors.to_h).to eq({})
    end

    it 'accepts a FieldStruct as the failure output' do
      result = action.run(mode: :fail_struct)
      expect(result.code).to eq(:rejected)
      expect(result.output.detail).to eq('st')
    end

    it 'ends as invalid_output carrying the invalid struct when the output breaks the schema' do
      result = action.run(mode: :fail_bad)
      expect(result.code).to eq(:invalid_output)
      expect(result).to be_failure
      expect(result.errors.to_h).to eq(detail: ['is required'])
      expect(result.output.valid?).to be(false)
    end

    it 'builds a skip output from its keywords' do
      result = action.run(mode: :skip)
      expect(result).to be_skipped
      expect(result.output.note).to eq('seen')
      expect(result.note).to eq('seen')
    end

    it 'never reads instance variables for a code with a schema' do
      result = action.run(mode: :skip_ivar)
      expect(result.code).to eq(:invalid_output)
      expect(result.errors.to_h).to eq(note: ['is required'])
    end

    it 'applies with typed outcomes on as well' do
      typed = Class.new(action) { typed_outcomes }
      expect(typed.run(mode: :fail)).to be_instance_of(typed::Failure)
      expect(typed.run(mode: :fail).output.detail).to eq('why')
    end

    it 'fail_with takes the output through output:' do
      side = Class.new(FieldStruct::Base) { required :x, :string }.new
      klass = action_with(setup: lambda {
        fails(:rejected) do
          required :detail, :string
        end
      }) { fail_with!(side, code: :rejected, output: { detail: 'd' }) }
      result = klass.run
      expect(result.code).to eq(:rejected)
      expect(result.output.detail).to eq('d')
      expect(result.errors[:x]).to eq(['is required'])
    end

    it 'the invalid_output failure carries the declared invalid_output metadata' do
      klass = action_with(setup: lambda {
        fails(:invalid_output, why: 'schema')
        fails(:rejected) { required :detail, :string }
      }) { fail!(:rejected) }
      expect(klass.run.metadata).to eq(why: 'schema')
    end
  end

  describe 'the output: keyword (AC-B#outputkw)' do
    it 'is an ordinary error key for a code without a schema when typed outcomes is off' do
      result = action_with { fail(:x, output: 'is bad') }.run
      expect(result.errors.to_h).to eq(output: ['is bad'])
    end

    it 'is the output under typed outcomes, even for a code without a schema (then judged)' do
      klass = action_with(setup: lambda {
        typed_outcomes
        fails(:plain)
      }) { fail(:plain, output: {}) }
      expect(klass.run.output).to eq({})
    end

    it 'fail_with still refuses it without a schema and without typed outcomes' do
      side = Class.new(FieldStruct::Base).new
      klass = action_with { fail_with(side, output: { a: 1 }) }
      expect { klass.run }.to raise_error(ArgumentError, /fail_with takes output: only under typed_outcomes/)
    end
  end

  describe 'codes without a schema (AC-B#typedempty, AC-B#outputrefused)' do
    it 'carry {} whatever the steps left behind' do
      klass = action_with(setup: lambda {
        typed_outcomes
        output { optional :note, :string }
        fails(:plain)
        skips(:quiet)
      }) do
        @note = 'x'
        @mode == :skip ? skip!(:quiet) : fail!(:plain)
      end
      klass.send(:define_method, :initialize) { |mode: nil| @mode = mode }
      expect(klass.run.output).to eq({})
      expect(klass.run(mode: :skip).output).to eq({})
    end

    it 'leave invalid_input at {} and invalid_output carrying the invalid struct' do
      klass = build_action do
        typed_outcomes
        input { required :n, :integer }
        output { required :fare, :integer }
        step :sail
        define_method(:sail) { nil }
      end
      expect(klass.run.output).to eq({})
      expect(klass.run(n: 1).output).to be_a(FieldStruct::Base)
    end

    it 'refuse non-empty failure output with a DefinitionError naming the fix' do
      klass = action_with(setup: lambda {
        typed_outcomes
        fails(:plain)
      }) { fail!(:plain, output: { a: 1 }) }
      expect { klass.run }.to raise_error(
        Actionable::DefinitionError,
        'action fails with :plain and output, but :plain declares no output schema; declare one with `fails :plain do … end`'
      )
    end

    it 'refuse non-empty skip output the same way' do
      klass = named_action('Typed::Skipper') do
        typed_outcomes
        skips(:plain)
        step :sail
        define_method(:sail) { skip!(:plain, a: 1) }
      end
      expect { klass.run }.to raise_error(
        Actionable::DefinitionError,
        'Typed::Skipper skips with :plain and output, but :plain declares no output schema; declare one with `skips :plain do … end`'
      )
    end

    it 'exempt the gem failure codes and accept an empty Hash' do
      klass = action_with(setup: -> { typed_outcomes }) { fail!(:invalid_input, output: { a: 1 }) }
      expect(klass.run.output).to eq(a: 1)
      empty = action_with(setup: lambda {
        typed_outcomes
        skips(:quiet)
      }) { skip!(:quiet) }
      expect(empty.run.output).to eq({})
    end

    it 'reject an output that is not a Hash or a FieldStruct' do
      klass = action_with(setup: lambda {
        typed_outcomes
        fails(:plain)
      }) { fail!(:plain, output: 5) }
      expect { klass.run }.to raise_error(ArgumentError, /output: must be a Hash or a FieldStruct, got Integer/)
    end

    it 'skip output stays best-effort when typed outcomes is off' do
      klass = action_with(setup: lambda {
        output { optional :existing_id, :integer }
        skips(:dup)
      }) { skip!(:dup, existing_id: 42) }
      expect(klass.run.existing_id).to eq(42)
    end

    it 'AC-B#declorder: the identifier check, then the declared check, then the output checks' do
      klass = action_with(setup: lambda {
        typed_outcomes
        fails(:plain)
      }) { fail!('not an identifier', output: { a: 1 }) }
      expect { klass.run }.to raise_error(ArgumentError, /is not an identifier/)
      other = action_with(setup: lambda {
        typed_outcomes
        fails(:plain)
      }) { fail!(:other, output: { a: 1 }) }
      expect { other.run }.to raise_error(Actionable::DefinitionError, /does not declare/)
    end
  end

  describe 'nested failures (AC-B#nestedtyped)' do
    let(:child) do
      named_action('Typed::Child') do
        typed_outcomes
        fails(:rejected) do
          required :detail, :string
          optional :extra, :string
        end
        step :sail
        define_method(:sail) { fail!(:rejected, output: { detail: 'child says', extra: 'e' }) }
      end
    end

    it 'becomes the parent own Failure, judged by the parent schema for the code' do
      kid = child
      parent = build_action do
        typed_outcomes
        fails(:rejected) { required :detail, :string }
        step kid
      end
      result = parent.run
      expect(result).to be_instance_of(parent::Failure)
      expect(result.code).to eq(:rejected)
      expect(result.output.class).to eq(parent.failure_output_schema(:rejected))
      expect(result.output.detail).to eq('child says')
      expect(result.output_fields_set).to eq([:detail])
    end

    it 'ends the parent as invalid_output when the child output breaks the parent schema' do
      kid = child
      parent = build_action do
        typed_outcomes
        fails(:rejected) do
          required :detail, :string
          required :other, :string
        end
        step kid
      end
      result = parent.run
      expect(result.code).to eq(:invalid_output)
      expect(result.errors.to_h).to eq(other: ['is required'])
    end

    it 'gives a parent without typed outcomes a plain Actionable::Failure, never the child class' do
      kid = child
      parent = build_action do
        fails(:rejected)
        step kid
      end
      result = parent.run
      expect(result.class).to eq(Actionable::Failure)
      expect(result.code).to eq(:rejected)
    end

    it 'still requires the parent to declare the code' do
      kid = child
      parent = build_action do
        typed_outcomes
        fails(:other)
        step kid
      end
      expect { parent.run }.to raise_error(Actionable::DefinitionError, /does not declare/)
    end

    it 'carries nothing for a code without a schema in the parent' do
      kid = child
      parent = build_action do
        typed_outcomes
        fails(:rejected)
        step kid
      end
      expect(parent.run.output).to eq({})
    end

    it 'crosses the gem codes with their output unchanged' do
      strict = named_action('Typed::Strict') do
        typed_outcomes
        output { required :fare, :integer }
        step :sail
        define_method(:sail) { nil }
      end
      parent = build_action do
        typed_outcomes
        fails(:rejected) { required :detail, :string }
        step strict
      end
      result = parent.run
      expect(result).to be_instance_of(parent::Failure)
      expect(result.code).to eq(:invalid_output)
      expect(result.output).to be_a(FieldStruct::Base)
      expect(result.output.valid?).to be(false)
      expect(result.errors.to_h).to eq(fare: ['is required'])
    end
  end
end
