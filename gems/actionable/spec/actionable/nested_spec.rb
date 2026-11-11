# frozen_string_literal: true

module NestedSpy
  private

  def record(section, step, &block)
    Thread.current[:nested_log]&.push([@instance.class, section, step.name, step.kind])
    super
  end
end

RSpec.describe 'Nested action steps' do
  let(:child) do
    named_action('NestedLine') do
      output do
        required :line, :integer
        optional :extra, :string
      end
      define_method(:initialize) { |berth: nil| @berth = berth }
      step :build

      private

      def build = @line = (@berth == 'a' ? 1 : 2)
    end
  end

  def parent_with(child_class, **options, &)
    build_action do
      define_method(:initialize) { |berth: 'a'| @berth = berth }
      attr_reader :seen

      step child_class, **options
      step :report
      class_eval(&) if block_given?
      private

      define_method(:report) { succeed(line: @line, other: @other, extra: @extra) }
      private :report
    end
  end

  it 'AC-B#nestedrun: input names become keywords from the parent ivars; unset ones pass nil' do
    child
    parent = parent_with(child, input: %i[berth])
    expect(parent.run(berth: 'b').output[:line]).to eq(2)
    got = nil
    spy = named_action('NestedSpyChild') do
      define_method(:initialize) { |**kw| got = kw }
    end
    build_action { step spy, input: %i[missing] }.run
    expect(got).to eq(missing: nil)
    no_args = nil
    plain = named_action('NestedPlain') { define_method(:initialize) { |*a, **k| no_args = [a, k] } }
    build_action { step plain }.run
    expect(no_args).to eq([[], {}])
  end

  it 'AC-B#nestedabsorb: only the fields the child actually set are copied; others keep the parent value' do
    child
    parent = parent_with(child, input: %i[berth]) do
      define_method(:initialize) do |berth: 'a'|
        @berth = berth
        @extra = 'keep'
        @other = 'keep'
      end
    end
    out = parent.run.output
    expect(out).to eq(line: 1, other: 'keep', extra: 'keep')
  end

  it 'AC-B#nestedabsorb: expose narrows the copied fields' do
    named_action('NestedTwo') do
      step :sail

      private

      def sail = succeed(line: 1, extra: 'x')
    end
    parent = parent_with(NestedTwo, expose: %i[line])
    expect(parent.run.output).to eq(line: 1, other: nil, extra: nil)
    all = parent_with(NestedTwo)
    expect(all.run.output).to eq(line: 1, other: nil, extra: 'x')
  end

  it 'AC-B#nestedabsorb: a skip is absorbed like a success and the parent continues' do
    named_action('NestedSkipper') do
      step :sail

      private

      def sail = skip!(:nothing, 'no', line: 5)
    end
    parent = parent_with(NestedSkipper)
    result = parent.run
    expect(result).to be_success
    expect(result.output[:line]).to eq(5)
  end

  it 'AC-B#nestedfail: the parent adopts the child failure, halts, and runs its failure hooks' do
    named_action('NestedBoom') do
      step :sail

      private

      def sail = fail!(:kraken, 'it broke', field: 'is bad')
    end
    log = []
    parent = build_action do
      step NestedBoom
      step :never
      on_failure :note
      define_method(:never) { log << :never }
      define_method(:note) { log << :note }
      private :never, :note
    end
    result = parent.run
    expect(result).to be_failure
    expect([result.code, result.message]).to eq([:kraken, 'it broke'])
    expect(result.errors.to_h).to eq(field: ['is bad'])
    expect(result.output).to eq({})
    expect(log).to eq([:note])
  end

  it 'AC-B#nestedfail: a host Failure subclass keeps its class and extra attributes' do
    stub_const('HostFailure', Class.new(Actionable::Failure) { optional :hint, :string })
    named_action('NestedHost') do
      step :sail

      private

      def sail
        @result = HostFailure.new(code: :custom, hint: 'try again', metadata: { retry: true })
        halt!
      end
    end
    result = build_action { step NestedHost }.run
    expect(result).to be_a(HostFailure)
    expect([result.code, result.hint, result.metadata]).to eq([:custom, 'try again', { retry: true }])
  end

  it 'AC-B#nestedinvalidinput: a child with invalid input fails with invalid_input in the parent' do
    named_action('NestedTyped') do
      input { required :n, :integer }
      step :sail

      private

      def sail = nil
    end
    result = build_action { step NestedTyped }.run
    expect(result.code).to eq(:invalid_input)
    expect(result.errors[:n]).to eq(['is required'])
  end

  it 'AC-B#nestedguard: an action step accepts if:/unless:' do
    child
    parent = parent_with(child, input: %i[berth], if: :never)
    parent.class_eval do
      private

      def never = false
    end
    expect(parent.run.output[:line]).to be_nil
  end

  it 'AC-B#hookaction: an action hook runs as an action step; a child failure adopts and stops the phase' do
    named_action('NestedHookBoom') do
      step :sail

      private

      def sail = fail!(:hook_boom)
    end
    log = []
    parent = build_action do
      on_success NestedHookBoom
      on_success :after
      always :tail
      define_method(:after) { log << :after }
      define_method(:tail) { log << :tail }
      private :after, :tail
    end
    result = parent.run
    expect(result.code).to eq(:hook_boom)
    expect(log).to eq([:tail])
  end

  it 'AC-B#stepdecl: an action step is named by the class and keyed by it' do
    child
    parent = build_action do
      step NestedLine, input: %i[a]
      step NestedLine, input: %i[b]
    end
    expect(parent.steps.size).to eq(1)
    expect(parent.steps.first.options).to eq(input: %i[b])
    expect([parent.steps.first.name, parent.steps.first.kind]).to eq([NestedLine, :action])
    expect(parent.steps.first).to be_a(Actionable::Steps::Action)
  end

  describe 'the record seam' do
    before { Actionable::Runner.prepend(NestedSpy) }

    after { Thread.current[:nested_log] = nil }

    it 'AC-B#recordseam: one parent call for the action step, the child records its own steps nested in time' do
      child
      Thread.current[:nested_log] = []
      parent = parent_with(child, input: %i[berth])
      parent.run
      log = Thread.current[:nested_log]
      expect(log.map { |entry| [entry[0] == parent, entry[2], entry[3]] }).to eq([
                                                                                   [true, NestedLine, :action],
                                                                                   [false, :build, :method],
                                                                                   [true, :report, :method]
                                                                                 ])
    end
  end
end
