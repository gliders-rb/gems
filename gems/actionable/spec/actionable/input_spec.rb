# frozen_string_literal: true

RSpec.describe 'Action input' do
  def typed(&input_block)
    build_action do
      input(&input_block)
      step :sail
      define_method(:sail) { succeed(seen: input.to_h) }
      private :sail
    end
  end

  it 'AC-B#inputdecl: builds a FieldStruct schema; no block reads; Action.input.new builds an instance' do
    action = typed { required :n, :integer }
    expect(action.input).to equal(action.input_schema)
    expect(action.input.new(n: '3').n).to eq(3)
  end

  it 'AC-B#inputnoblock: without input, the reader and the schema are nil' do
    action = build_action do
      step :sail
      define_method(:sail) { succeed(input: input.inspect) }
      private :sail
    end
    expect(action.input).to be_nil
    expect(action.input_schema).to be_nil
    expect(action.input_dispatch).to be_nil
    expect(action.run.output).to eq(input: 'nil')
  end

  it 'AC-B#typedrun: builds from keywords, coerces, exposes input to the steps; string keys work' do
    action = typed { required :n, :integer }
    expect(action.run(n: '21').output).to eq(seen: { n: 21 })
    expect(action.run('n' => 4).output).to eq(seen: { n: 4 })
  end

  it 'AC-B#typedrun: unknown keywords are dropped' do
    expect(typed { required :n, :integer }.run(n: 1, extra: 2).output).to eq(seen: { n: 1 })
  end

  it 'AC-B#typedrun: an initialize that needs arguments makes .run raise Ruby\'s ArgumentError' do
    action = build_action do
      input { required :n, :integer }
      define_method(:initialize) do |required_arg|
        super()
        @x = required_arg
      end
    end
    expect { action.run(n: 1) }.to raise_error(ArgumentError)
  end

  it 'AC-B#typedrun: an initialize with no required arguments that calls super works' do
    action = build_action do
      input { required :n, :integer }
      step :sail
      define_method(:initialize) do |*|
        super()
        @extra = :set
      end
      define_method(:sail) { succeed(extra: @extra, n: input.n) }
      private :sail
    end
    expect(action.run(n: 2).output).to eq(extra: :set, n: 2)
  end

  describe 'invalid input' do
    it 'AC-B#invalidinput: runs no step, returns Failure(:invalid_input) with the struct errors' do
      ran = []
      action = build_action do
        input { required :n, :integer }
        step :sail
        define_method(:sail) { ran << :sail }
        private :sail
      end
      result = action.run
      expect(ran).to be_empty
      expect(result).to be_a(Actionable::Failure)
      expect([result.code, result.message, result.output, result.metadata]).to eq([:invalid_input, 'input failed validation', {}, {}])
      expect(result.errors[:n]).to eq(['is required'])
      expect(action.run(n: 'x').errors[:n].first).to start_with('could not be coerced')
    end

    it 'AC-B#invalidinput: the invalid-input failure skips the missing-method check' do
      action = build_action do
        input { required :n, :integer }
        step :missing_method_here
      end
      expect(action.run.code).to eq(:invalid_input)
    end

    it 'AC-B#nestedinput: a nested struct field takes a Hash or an instance; invalid nested reports only the field' do
      mooring = Class.new(FieldStruct::Base) { required :port, :string }
      action = typed do
        required :home, mooring
      end
      expect(action.run(home: { port: 'Lima' }).output.dig(:seen, :home)).to be_a(mooring)
      result = action.run(home: {})
      expect([result.code, result.errors.to_h]).to eq([:invalid_input, { home: ['is invalid'] }])
    end
  end

  describe 'positional arguments' do
    it 'AC-B#inputinstance: a single instance of the schema is used as is' do
      action = typed { required :n, :integer }
      instance = action.input.new(n: 5)
      expect(action.run(instance).output).to eq(seen: { n: 5 })
    end

    it 'AC-B#inputinstance: any other positional argument, a Hash included, is ignored' do
      action = typed { required :n, :integer }
      result = action.run({ n: 1 })
      expect([result.code, result.errors[:n]]).to eq([:invalid_input, ['is required']])
    end
  end

  it 'AC-B#unknownraise: unknown_attributes :raise makes .run itself raise' do
    action = build_action do
      input do
        unknown_attributes :raise
        required :n, :integer
      end
    end
    expect { action.run(n: 1, extra: 2) }.to raise_error(FieldStruct::UnknownAttributeError)
  end

  describe 'input_for dispatch' do
    let(:freight) { Class.new(FieldStruct::Base) { required :tonnage, :integer } }
    let(:rebate) { Class.new(FieldStruct::Base) { required :reason, :string } }
    let(:other) { Class.new(FieldStruct::Base) { optional :note, :string } }
    let(:action) do
      s = freight
      r = rebate
      o = other
      build_action do
        input_for(:manifest_kind) do
          on 'freight', s
          on %w[rebate return], r
          default o
        end
        step :sail
        define_method(:sail) { succeed(shape: input.class, values: input.to_h) }
        private :sail
      end
    end

    it 'AC-B#inputfor: picks the schema from the discriminator keyword, first match then default' do
      expect(action.run(manifest_kind: 'freight', tonnage: '5').output).to eq(shape: freight, values: { tonnage: 5 })
      expect(action.run(manifest_kind: 'return', reason: 'x').output[:shape]).to eq(rebate)
      expect(action.run(manifest_kind: 'weird', note: 'n').output[:shape]).to eq(other)
    end

    it 'AC-B#inputfor: a chosen schema is validated like a fixed input' do
      result = action.run(manifest_kind: 'freight')
      expect([result.code, result.errors[:tonnage]]).to eq([:invalid_input, ['is required']])
    end

    it 'AC-B#dispatchunmatched: no match and no default fails with a named message' do
      s = freight
      bare = build_action { input_for(:manifest_kind) { on 'freight', s } }
      result = bare.run(manifest_kind: 'wat')
      expect([result.code, result.message, result.errors.to_h, result.metadata]).to eq(
        [:invalid_input, 'no input shape for manifest_kind "wat"', {}, {}]
      )
      expect(bare.run.message).to eq('no input shape for manifest_kind nil')
      expect(bare.run('manifest_kind' => 'freight').message).to eq('no input shape for manifest_kind nil')
    end

    it 'AC-B#dispatchinstance: a single positional instance of any reachable schema is accepted as is' do
      expect(action.run(rebate.new(reason: 'r')).output[:shape]).to eq(rebate)
      expect(action.run(other.new).output[:shape]).to eq(other)
    end

    it 'AC-B#dispatchprecedence: the dispatch decides when both input and input_for are declared' do
      s = freight
      both = build_action do
        input { required :never, :string }
        input_for('kind') { default s }
        step :sail
        define_method(:sail) { succeed(shape: input.class) }
        private :sail
      end
      expect(both.input_dispatch.discriminator).to eq(:kind)
      expect(both.input_schema).not_to be_nil
      expect(both.run(tonnage: 1).output).to eq(shape: freight)
    end

    it 'AC-B#inputdispatch: branches, variants, schemas, schema_for and default_schema' do
      dispatch = action.input_dispatch
      expect(dispatch).to be_a(Actionable::InputDispatch)
      expect(dispatch.discriminator).to eq(:manifest_kind)
      expect(dispatch.branches).to eq([['freight', freight], [%w[rebate return], rebate]])
      expect(dispatch.variants).to eq(['freight', %w[rebate return]])
      expect(dispatch.default_schema).to equal(other)
      expect(dispatch.schema_for('return')).to equal(rebate)
      expect(dispatch.schema_for('x')).to equal(other)
      expect(dispatch.schemas).to eq([freight, rebate, other])
    end

    it 'AC-B#inputdispatch: schema_for is nil without a default; schemas de-duplicates' do
      s = freight
      dispatch = Actionable::InputDispatch.define(:k) do
        on 'a', s
        on 'b', s
      end
      expect(dispatch.schema_for('z')).to be_nil
      expect(dispatch.schemas).to eq([freight])
    end

    it 'AC-B#inputdispatch: is shared by subclasses' do
      expect(build_action(action).input_dispatch).to equal(action.input_dispatch)
    end
  end
end
