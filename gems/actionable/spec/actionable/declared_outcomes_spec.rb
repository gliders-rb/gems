# frozen_string_literal: true

RSpec.describe 'Declared failures and skips' do
  describe 'declaration' do
    it 'AC-B#declare: stores message and frozen metadata, normalizes codes, returns declared_failures' do
      action = build_action
      returned = action.fails('refused', 'not allowed', retry: false)
      expect(returned).to eq(refused: { retry: false })
      expect(action.declared_failures[:refused]).to be_frozen
      expect(action.failure_declarations).to eq(refused: { message: 'not allowed', metadata: { retry: false } })
      expect(action.skips(:later, 'not yet')).to eq(later: {})
      expect(action.skip_declarations).to eq(later: { message: 'not yet', metadata: {} })
    end

    it 'AC-B#declread: the schema key is present only when the declaration had a block' do
      action = build_action do
        fails(:plain)
        fails(:typed) { required :detail, :string }
        skips(:typed_skip) { optional :note, :string }
      end
      expect(action.failure_declarations[:plain].keys).to eq(%i[message metadata])
      expect(action.failure_declarations[:typed].keys).to eq(%i[message metadata output_schema])
      expect(action.failure_output_schema(:typed).attribute_names).to eq([:detail])
      expect(action.failure_output_schema('typed')).to eq(action.failure_output_schema(:typed))
      expect(action.failure_output_schema(:plain)).to be_nil
      expect(action.skip_output_schema(:typed_skip).attribute_names).to eq([:note])
      expect(action.skip_output_schema(:adrift)).to be_nil
    end

    it 'AC-B#reservedout: an output block on fails/skips refuses reserved names' do
      expect { build_action { fails(:x) { required :status, :string } } }
        .to raise_error(Actionable::DefinitionError, /output field\(s\) :status conflict/)
      expect { build_action { skips(:x) { required :code, :string } } }
        .to raise_error(Actionable::DefinitionError, /:code/)
    end

    it 'AC-B#declare: subclasses inherit by snapshot, can add, and redeclaring without a block drops the schema' do
      parent = build_action do
        fails(:a, 'first') { required :d, :string }
        skips :s
      end
      child = build_action(parent) do
        fails :a, 'second'
        fails :b
      end
      parent.fails :late
      expect(child.declared_failures.keys).to eq(%i[a b])
      expect(child.failure_declarations[:a]).to eq(message: 'second', metadata: {})
      expect(parent.failure_output_schema(:a)).not_to be_nil
      expect(child.declared_skips.keys).to eq([:s])
      expect(child.skip_declarations).not_to equal(parent.skip_declarations)
    end

    it 'AC-B#declgem: a block on a gem failure code raises ArgumentError at declaration' do
      action = build_action
      [:invalid_input, 'invalid_output'].each do |code|
        expect { action.fails(code) { required :x, :string } }.to raise_error(
          ArgumentError,
          "action: :#{code} is a gem failure code and cannot declare an output schema; remove the block " \
          '(the gem builds this failure itself)'
        )
      end
      named = named_action('GemBlock') { nil }
      expect { named.fails(:invalid_input) { nil } }.to raise_error(ArgumentError, /\AGemBlock: :invalid_input/)
    end
  end

  describe 'carrying metadata and messages' do
    let(:action) do
      build_action do
        fails :refused, 'not allowed', retry: false
        fails :nomsg, nil, kind: 'x'
        skips :already, 'already done', retry: true
        step :sail
        define_method(:sail) do
          verbs = {
            fail: -> { fail(:refused) }, fail_msg: -> { fail(:refused, 'custom') }, fail_bang: -> { fail!(:refused) },
            fail_with: -> { fail_with(FieldStruct::Base.new, code: :refused) },
            fail_with_bang: -> { fail_with!(FieldStruct::Base.new, code: :refused, message: 'mine') },
            skip: -> { skip(:already) }, skip_bang: -> { skip!(:already, 'again') }, nomsg: -> { fail!(:nomsg) }
          }
          instance_exec(&verbs.fetch(@mode))
        end
        define_method(:initialize) { |mode: nil| @mode = mode }
        private :sail
      end
    end

    it 'AC-B#declcarry: a declared failure carries the metadata and the default message' do
      %i[fail fail_bang fail_with].each do |mode|
        result = action.run(mode: mode)
        expect([result.code, result.message, result.metadata]).to eq([:refused, 'not allowed', { retry: false }])
      end
    end

    it 'AC-B#declcarry: an explicit message wins' do
      expect(action.run(mode: :fail_msg).message).to eq('custom')
      expect(action.run(mode: :fail_with_bang).message).to eq('mine')
    end

    it 'AC-B#declcarry: a declaration without message leaves it nil' do
      result = action.run(mode: :nomsg)
      expect([result.message, result.metadata]).to eq([nil, { kind: 'x' }])
    end

    it 'AC-B#declcarry: skips do the same' do
      result = action.run(mode: :skip)
      expect([result.code, result.message, result.metadata]).to eq([:already, 'already done', { retry: true }])
      expect(action.run(mode: :skip_bang).message).to eq('again')
    end

    it 'AC-B#declcarry: an undeclared code in an action declaring none has empty metadata' do
      plain = build_action do
        step :sail
        define_method(:sail) { fail!(:whatever) }
        private :sail
      end
      expect(plain.run.metadata).to eq({})
    end

    it 'AC-B#declgem: declared metadata attaches to the gem-built failures' do
      typed = build_action do
        input { required :n, :integer }
        output { required :fare, :integer }
        fails :invalid_input, nil, retry: false
        fails 'invalid_output', nil, beacon: true
        step :sail
        define_method(:sail) { nil }
        private :sail
      end
      expect(typed.run.metadata).to eq(retry: false)
      expect(typed.run(n: 1).metadata).to eq(beacon: true)
      expect(typed.run(n: 1).code).to eq(:invalid_output)
    end

    it 'AC-B#declgem: undeclared, the gem failures have empty metadata' do
      typed = build_action { input { required :n, :integer } }
      expect(typed.run.metadata).to eq({})
    end
  end

  describe 'strictness' do
    let(:strict) do
      build_action do
        fails :refused
        fails :not_found
        skips :not_ready
        step :sail
        define_method(:initialize) { |verb: nil, code: nil| @verb = verb, code }
        define_method(:sail) do
          verb, code = @verb
          case verb
          when :fail then fail(code)
          when :fail_with then fail_with(FieldStruct::Base.new)
          when :skip then skip(code)
          when :skip_default then skip!
          end
        end
        private :sail
      end
    end

    it 'AC-B#declstrict: an undeclared failure code raises DefinitionError at the call' do
      expect { strict.run(verb: :fail, code: :other) }.to raise_error(
        Actionable::DefinitionError,
        'action fails with :other, which it does not declare; declare it with `fails :other` ' \
        '(declared: :refused, :not_found)'
      )
    end

    it 'AC-B#declstrict: declared codes and gem codes pass; fail_with default :invalid is refused' do
      expect(strict.run(verb: :fail, code: :refused).code).to eq(:refused)
      expect(strict.run(verb: :fail, code: :invalid_input).code).to eq(:invalid_input)
      expect(strict.run(verb: :fail, code: 'not_found').code).to eq(:not_found)
      expect { strict.run(verb: :fail_with) }.to raise_error(Actionable::DefinitionError, /fails with :invalid,/)
    end

    it 'AC-B#declstrictskip: skips are strict too, even the implicit :skipped' do
      expect(strict.run(verb: :skip, code: :not_ready).code).to eq(:not_ready)
      expect { strict.run(verb: :skip, code: :other) }.to raise_error(
        Actionable::DefinitionError,
        'action skips with :other, which it does not declare; declare it with `skips :other` (declared: :not_ready)'
      )
      expect { strict.run(verb: :skip_default) }.to raise_error(Actionable::DefinitionError, /skips with :skipped/)
    end

    it 'AC-B#declstrictskip: declaring failures does not make skips strict, and vice versa' do
      failures_only = build_action do
        fails :refused
        step :sail
        define_method(:sail) { skip!(:anything) }
        private :sail
      end
      skips_only = build_action do
        skips :later
        step :sail
        define_method(:sail) { fail!(:anything) }
        private :sail
      end
      expect(failures_only.run).to be_skipped
      expect(skips_only.run).to be_failure
    end

    it 'AC-B#declorder: the identifier check runs before the declared check' do
      expect { strict.run(verb: :fail, code: 'not an id') }.to raise_error(ArgumentError, /is not an identifier/)
      expect { strict.run(verb: :skip, code: 'not an id') }.to raise_error(ArgumentError, /is not an identifier/)
    end

    it 'AC-B#allowsf: allows_failure_code? with no declarations, declared (String or Symbol) and gem codes' do
      expect(build_action.allows_failure_code?(:anything)).to be(true)
      expect(strict.allows_failure_code?('refused')).to be(true)
      expect(strict.allows_failure_code?(:invalid_output)).to be(true)
      expect(strict.allows_failure_code?(:other)).to be(false)
    end

    it 'AC-B#allowss: allows_skip_code? has no gem exemption' do
      expect(build_action.allows_skip_code?(:anything)).to be(true)
      expect(strict.allows_skip_code?('not_ready')).to be(true)
      expect(strict.allows_skip_code?(:invalid_input)).to be(false)
      expect(strict.allows_skip_code?(:skipped)).to be(false)
    end
  end

  describe 'nested actions' do
    before do
      named_action('DeclChild') do
        fails :child_code, 'child default', from_child: 1
        skips :child_skip
        step :sail
        define_method(:initialize) { |mode: :fail, message: nil| @mode = mode, message }
        define_method(:sail) do
          mode, message = @mode
          case mode
          when :fail then fail!(:child_code, message)
          when :skip then skip!(:child_skip)
          when :other then fail!(:child_code)
          end
        end
        private :sail
      end
    end

    def parent(&)
      build_action do
        define_method(:initialize) do |mode: :fail, message: nil|
          @mode = mode
          @message = message
        end
        step DeclChild, input: %i[mode message]
        class_eval(&) if block_given?
      end
    end

    it 'AC-B#nesteddeclare: a parent declaring failures must declare the child codes' do
      strict = parent { fails :mine }
      expect { strict.run }.to raise_error(
        Actionable::DefinitionError, /fails with :child_code, which it does not declare.*\(declared: :mine\)/
      )
    end

    it 'AC-B#nestedfail: the adopted failure takes the parent default message when the child has none, and merged metadata' do
      declared_child = Class.new(DeclChild)
      declared_child.fails :child_code, nil, from_child: 2
      stub_const('NoMessageChild', declared_child)
      with_default = build_action do
        fails :child_code, 'parent default', from_parent: true, from_child: 0
        step NoMessageChild
      end
      result = with_default.run
      expect(result.message).to eq('parent default')
      expect(result.metadata).to eq(from_parent: true, from_child: 2)
    end

    it 'AC-B#nestedfail: the child message wins over the parent default' do
      with_default = parent { fails :child_code, 'parent default', own: 1 }
      result = with_default.run(message: 'from child')
      expect(result.message).to eq('from child')
      expect(result.metadata).to eq(own: 1, from_child: 1)
    end

    it 'AC-B#nestedfail: with no parent declarations the child metadata is kept as is' do
      result = parent.run
      expect([result.code, result.message, result.metadata]).to eq([:child_code, 'child default', { from_child: 1 }])
    end

    it 'AC-B#nestedskip: a parent declaring skips does not declare the child skip codes' do
      skipping = parent { skips :mine }
      result = skipping.run(mode: :skip)
      expect(result).to be_success
    end

    it 'AC-B#nestedinvalidinput: gem codes cross into a parent declaring other codes' do
      named_action('DeclTyped') do
        input { required :n, :integer }
        step :sail

        private

        def sail = nil
      end
      crossing = build_action do
        fails :mine
        step DeclTyped
      end
      expect(crossing.run.code).to eq(:invalid_input)
    end
  end

  describe 'introspection' do
    let(:action) do
      build_action do
        fails :refused, 'not allowed', retry: false
        fails(:typed, 'typed') { required :detail, :string }
        fails :bare
        skips :later, 'not yet'
      end
    end

    it 'AC-B#describe: failures and skips with message, metadata and output' do
      info = action.describe
      expect(info[:failures][:refused]).to eq(message: 'not allowed', metadata: { retry: false })
      expect(info[:failures][:typed][:output]).to eq(action.failure_output_schema(:typed).metadata.to_h)
      expect(info[:failures][:bare]).to eq(message: nil, metadata: {})
      expect(info[:skips]).to eq(later: { message: 'not yet', metadata: {} })
    end

    it 'AC-B#describetext: Failures and Skips sections' do
      text = action.describe_text
      expect(text).to include("  Failures:\n    - refused (retry: false): not allowed\n    - typed: typed\n    - bare\n")
      expect(text).to include("  Skips:\n    - later: not yet")
      expect(text.index('Failures:')).to be < text.index('Skips:')
    end
  end
end
