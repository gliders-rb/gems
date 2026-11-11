# frozen_string_literal: true

require 'actionable/rspec'

RSpec.describe 'RSpec stub helpers' do
  let(:plain) { build_action }
  let(:declared) do
    named_action('StubDeclared') do
      fails :refused, 'not allowed', retry: false
      fails :other
      skips :later, 'not yet', retry: true
    end
  end

  describe 'stubbing run (AC-B#stubs)' do
    it 'allow_* answers run for any arguments with a real result, and returns it' do
      result = allow_actionable_success(plain, message: 'ok', output: { id: 5 })
      expect(plain.run).to equal(result)
      expect(plain.run(1, a: 2)).to equal(result)
      expect(result).to be_a(Actionable::Success)
      expect([result.message, result.output]).to eq(['ok', { id: 5 }])
    end

    it 'allow_* does not require the call' do
      expect { allow_actionable_failure(plain) }.not_to raise_error
    end

    it 'stub_* also expects run to be called' do
      expect do
        RSpec::Mocks.with_temporary_scope { stub_actionable_success(plain) }
      end.to raise_error(RSpec::Mocks::MockExpectationError)
      RSpec::Mocks.with_temporary_scope do
        stub_actionable_skip(plain)
        plain.run
      end
    end

    it 'builds failures and skips with their keywords' do
      failure = allow_actionable_failure(plain, code: :kraken, message: 'bad', errors: { name: 'is bad', age: %w[a b] },
                                                metadata: { x: 1 })
      expect(plain.run).to equal(failure)
      expect([failure.code, failure.message, failure.metadata]).to eq([:kraken, 'bad', { x: 1 }])
      expect(failure.errors.to_h).to eq(name: ['is bad'], age: %w[a b])
      skip = stub_actionable_skip(plain, code: :quiet, message: 'ebb', output: { a: 1 }, metadata: { y: 2 })
      expect(plain.run).to equal(skip)
      expect([skip.code, skip.message, skip.output, skip.metadata]).to eq([:quiet, 'ebb', { a: 1 }, { y: 2 }])
    end

    it 'defaults: failure code :error, skip code :skipped' do
      expect(allow_actionable_failure(plain).code).to eq(:error)
      expect(allow_actionable_skip(plain).code).to eq(:skipped)
    end
  end

  describe 'builders (AC-B#stubbuilders)' do
    it 'build plain results without stubbing anything' do
      success = actionable_success_result(message: 'm', output: { a: 1 }, errors: { base: 'oops' })
      failure = actionable_failure_result(code: :adrift, errors: { f: %w[x y] }, metadata: { k: 1 })
      skip = actionable_skip_result(code: :later)
      expect(success).to be_success
      expect(success.errors.to_h).to eq(base: ['oops'])
      expect(failure.errors.to_h).to eq(f: %w[x y])
      expect([failure.metadata, skip.code]).to eq([{ k: 1 }, :later])
      expect(actionable_failure_result.code).to eq(:error)
      expect(actionable_skip_result.code).to eq(:skipped)
    end
  end

  describe 'declaration awareness (AC-B#stubdeclared)' do
    it 'attaches the declared metadata and message of a failure code' do
      failure = allow_actionable_failure(declared, code: :refused)
      expect(failure.message).to eq('not allowed')
      expect(failure.metadata).to eq(retry: false)
      expect(allow_actionable_failure(declared, code: :refused, message: 'mine').message).to eq('mine')
    end

    it 'lets an explicit metadata override the declared keys' do
      failure = allow_actionable_failure(declared, code: :refused, metadata: { retry: true, extra: 1 })
      expect(failure.metadata).to eq(retry: true, extra: 1)
    end

    it 'raises ArgumentError for an undeclared failure code, allowing gem codes' do
      expect { allow_actionable_failure(declared, code: :ebb) }.to raise_error(
        ArgumentError,
        'StubDeclared does not declare :ebb (declared: :refused, :other); a stub or and_fail with it tests a failure ' \
        'the action can never return'
      )
      expect(allow_actionable_failure(declared, code: :invalid_input).code).to eq(:invalid_input)
      expect(allow_actionable_failure(plain, code: :anything).code).to eq(:anything)
    end

    it 'mirrors this for skips, with the default :skipped not exempt' do
      skip = allow_actionable_skip(declared, code: :later)
      expect([skip.message, skip.metadata]).to eq(['not yet', { retry: true }])
      expect { allow_actionable_skip(declared, code: :ebb) }.to raise_error(
        ArgumentError,
        'StubDeclared does not declare skip :ebb (declared: :later); a stub or and_skip with it tests a skip the action can never return'
      )
      expect { allow_actionable_skip(declared) }.to raise_error(ArgumentError, /does not declare skip :skipped/)
      expect(allow_actionable_skip(plain).code).to eq(:skipped)
    end
  end

  describe 'output shape (AC-B#stubshape)' do
    it 'keeps the given Hash for an action without typed outcomes' do
      action = build_action { output { required :id, :integer } }
      result = allow_actionable_success(action, output: { id: 5 })
      expect(result.output).to eq(id: 5)
      expect { result.id }.to raise_error(NoMethodError)
    end

    context 'with typed outcomes' do
      let(:typed) do
        named_action('StubTyped') do
          typed_outcomes
          output { required :id, :integer }
          fails(:rejected) { required :detail, :string }
          fails(:plain)
          skips(:note) { optional :text, :string }
          skips(:quiet)
        end
      end

      it 'builds the success output through the success schema and sets output_fields_set' do
        result = allow_actionable_success(typed, output: { id: '7', ignored: 1 })
        expect(result).to be_instance_of(typed::Success)
        expect(result.id).to eq(7)
        expect(result.output_fields_set).to eq([:id])
      end

      it 'raises when the output breaks the schema' do
        expect { allow_actionable_success(typed, output: {}) }.to raise_error(
          ArgumentError,
          'StubTyped output for :success breaks its schema (Id is required); a real run would end as invalid_output'
        )
      end

      it 'builds failure and skip output through the code schema, as the action own classes' do
        failure = allow_actionable_failure(typed, code: :rejected, output: { detail: 'd' })
        expect(failure).to be_instance_of(typed::Failure)
        expect(failure.detail).to eq('d')
        skip = allow_actionable_skip(typed, code: :note, output: { text: 't' })
        expect(skip).to be_instance_of(typed::Skipped)
        expect(skip.output.text).to eq('t')
      end

      it 'refuses non-empty output for a code without a schema, accepts empty, keeps gem code output' do
        expect { allow_actionable_failure(typed, code: :plain, output: { a: 1 }) }.to raise_error(
          ArgumentError, 'StubTyped output for :plain, which declares no output schema; a real run refuses it'
        )
        expect(allow_actionable_failure(typed, code: :plain).output).to eq({})
        expect(allow_actionable_skip(typed, code: :quiet).output).to eq({})
        expect { allow_actionable_skip(typed, code: :quiet, output: { a: 1 }) }.to raise_error(ArgumentError, /declares no output schema/)
        expect(allow_actionable_failure(typed, code: :invalid_input, output: { a: 1 }).output).to eq(a: 1)
      end
    end

    it 'shapes a code with a schema even without typed outcomes' do
      action = named_action('StubSchemaOnly') { fails(:rejected) { required :detail, :string } }
      failure = allow_actionable_failure(action, code: :rejected, output: { detail: 'x' })
      expect(failure.output).to be_a(FieldStruct::Base)
      expect(failure.class).to eq(Actionable::Failure)
      expect { allow_actionable_failure(action, code: :rejected) }.to raise_error(ArgumentError, /breaks its schema/)
    end
  end

  describe 'inside a parent action step (AC-B#stubparent)' do
    it 'contributes only the fields the stub was given' do
      child = named_action('StubChild') do
        typed_outcomes
        output do
          optional :line, :integer
          optional :extra, :string
        end
      end
      allow_actionable_success(child, output: { line: 3 })
      parent = build_action do
        step child
        step :check
        define_method(:initialize) { @extra = 'keep' }
        define_method(:check) { succeed(extra: @extra, line: @line) }
        output do
          optional :line, :integer
          optional :extra, :string
        end
      end
      result = parent.run
      expect([result.line, result.extra]).to eq([3, 'keep'])
    end
  end

  describe 'coverage notes (AC-B#stubcoverage)' do
    it 'records each answered call when Actionable::Coverage is loaded' do
      notes = []
      coverage = Module.new
      coverage.define_singleton_method(:record_stub) { |*args| notes << args }
      stub_const('Actionable::Coverage', coverage)
      action = named_action('StubCovered') { fails :x }
      allow_actionable_failure(action, code: :x)
      allow_actionable_skip(plain)
      action.run
      action.run
      expect(notes).to eq([['StubCovered', :failure, :x], ['StubCovered', :failure, :x]])
    end

    it 'does nothing when Coverage is not loaded' do
      allow_actionable_success(plain)
      expect { plain.run }.not_to raise_error
    end
  end
end
