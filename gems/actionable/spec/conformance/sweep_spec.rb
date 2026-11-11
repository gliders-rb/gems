# frozen_string_literal: true

require 'oj'

# Examples added by the slice 13 conformance sweep: rules that had no tagged example before.
RSpec.describe 'conformance sweep' do
  def action(&block)
    Class.new(Actionable::Action, &block)
  end

  describe 'AC-B#abstractreaders' do
    it 'class-level readers exist without running, and are inherited' do
      parent = action do
        typed_outcomes
        fails :broke, 'it broke', retry: false
        skips :done
      end
      child = Class.new(parent)
      [parent, child].each do |klass|
        expect(klass.declared_failures).to eq(broke: { retry: false })
        expect(klass.declared_skips).to eq(done: {})
        expect(klass.failure_declarations.keys).to eq([:broke])
        expect(klass.skip_declarations.keys).to eq([:done])
        expect(klass.typed_outcomes?).to be(true)
      end
      expect(action.declared_failures).to eq({})
    end
  end

  describe 'AC-B#schemareaders' do
    it 'builds anonymous schemas, nil when absent, and input_dispatch only after input_for' do
      plain = action
      expect([plain.input_schema, plain.output_schema, plain.input_dispatch]).to all(be_nil)
      declared = action do
        input { required :a, :integer }
        output { optional :b, :string }
      end
      expect(declared.input_schema.name).to be_nil
      expect(declared.output_schema.attribute_names).to eq([:b])
      expect(declared.input_schema.new(a: 1).a).to eq(1)
      expect(Class.new(declared).input_schema).to equal(declared.input_schema)
      shape = Class.new(FieldStruct::Base) { required :x, :integer }
      dispatched = action { input_for(:k) { on 'a', shape } }
      expect(dispatched.input_dispatch).to be_a(Actionable::InputDispatch)
    end
  end

  describe 'AC-B#errorsshape' do
    it 'is a FieldStruct::Errors whose to_h is a fresh Symbol-keyed Hash of String arrays' do
      klass = action do
        step :sail
        define_method(:sail) { fail!(:bad, 'msg', 'name' => 'bad', tags: %w[a b]) }
      end
      result = klass.run
      expect(result.errors).to be_a(FieldStruct::Errors)
      expect(result.errors.to_h).to eq(name: ['bad'], tags: %w[a b])
      expect(result.errors.to_h).not_to equal(result.errors.to_h)
      expect(Oj.dump(result.errors.to_h, mode: :compat)).to eq('{"name":["bad"],"tags":["a","b"]}')
      expect(Actionable::Success.new.errors.to_h).to eq({})
    end

    it 'uses the schema field names for input validation failures' do
      klass = action { input { required :n, :integer } }
      expect(klass.run.errors.to_h).to eq(n: ['is required'])
    end
  end

  describe 'AC-B#outputshape' do
    it 'is a schema instance, a Hash, or a code-schema instance, and never nil' do
      with_schema = action do
        output { required :n, :integer }
        step :sail
        define_method(:sail) { @n = 1 }
      end
      expect(with_schema.run.output).to be_a(with_schema.output_schema)
      free = action do
        step :sail
        define_method(:sail) { nil }
      end
      expect(free.run.output).to eq({})
      kw = action do
        step :sail
        define_method(:sail) { succeed(x: 1) }
      end
      expect(kw.run.output).to eq(x: 1)
      bad = action { input { required :n, :integer } }
      expect(bad.run.output).to eq({})
      coded = action do
        fails(:no) { required :why, :string }
        step :sail
        define_method(:sail) { fail!(:no, output: { why: 'x' }) }
      end
      expect(coded.run.output.why).to eq('x')
      expect(Oj.dump(coded.run.output.as_json, mode: :compat)).to eq('{"why":"x"}')
    end
  end

  describe 'AC-B#successnometa' do
    it 'Success lacks metadata, Failure and Skipped have it, codes are Symbols' do
      expect(Actionable::Success.new).not_to respond_to(:metadata)
      expect(Actionable::Failure.new(code: :a).metadata).to eq({})
      expect(Actionable::Skipped.new(code: :b).metadata).to eq({})
      typed = action { typed_outcomes }
      expect(typed.run).not_to respond_to(:metadata)
      expect(typed.run.code).to eq(:success)
      codes = action do
        fails 'odd?'
        step :sail
        define_method(:sail) { fail!('odd?') }
      end
      expect(codes.run.code).to eq(:odd?)
    end
  end

  describe 'AC-B#dispatchruntype' do
    it 'describes the discriminator and types run as (*untyped)' do
      shape = Class.new(FieldStruct::Base) { required :x, :integer }
      stub_const('Dispatched', action { input_for(:k) { on 'a', shape } })
      expect(Dispatched.describe[:input]).to include(discriminated_on: :k)
      expect(Actionable::RBS.generate(Dispatched)).to include('def self.run: (*untyped)')
    end
  end

  describe 'AC-B#hooktimes and AC-B#nestedhistory' do
    it 'times the whole child run in the parent step record and attaches the child history' do
      child = action do
        measure :all
        step :work
        define_method(:work) { sleep 0.02 }
      end
      parent = action do
        measure :all
        step child
      end
      record = parent.run.history.steps.first
      expect(record.duration).to be >= 0.02
      expect(record.nested).to be_a(Actionable::History)
      expect(record.nested.steps.map(&:name)).to eq([:work])
    end
  end

  describe 'AC-B#covpartial and AC-B#ci' do
    it 'documentation tells hosts to set the baseline only in CI' do
      root = File.expand_path('../..', __dir__)
      usage = File.read(File.join(root, 'USAGE.md'))
      expect(usage).to match(/baseline.*CI only/)
      expect(usage).to include('only_observed')
    end

    it 'the workflow is scoped to actionable and field_struct and has the spec lanes' do
      workflow = File.read(File.expand_path('../../../../.github/workflows/actionable.yml', __dir__))
      expect(workflow).to include("'gems/actionable/**'", "'gems/field_struct/**'")
      expect(workflow).to include("['3.3', '3.4', '4.0']", 'release:check', 'active_record_71', 'spec:job', 'types:report')
      expect(workflow).to match(/types:.*continue-on-error: true/m)
    end
  end
end
