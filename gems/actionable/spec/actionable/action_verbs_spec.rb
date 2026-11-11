# frozen_string_literal: true

RSpec.describe Actionable::Action do
  describe 'plain verbs' do
    it 'AC-B#plainverbs: succeed records a Success with the keywords as output and returns true' do
      action = build_action do
        step :sail

        attr_reader :returned

        private

        def sail
          @returned = succeed('done', a: 1)
        end
      end
      result = action.run
      expect(result).to be_a(Actionable::Success)
      expect([result.message, result.output]).to eq(['done', { a: 1 }])
    end

    it 'AC-B#plainverbs: fail records a Failure with errors and returns false; later steps still run' do
      seen = []
      action = build_action do
        step :first
        step :second
        define_method(:first) { seen << fail(:adrift, 'no way', name: 'bad', tags: %w[x y]) }
        define_method(:second) { seen << :second_ran }
        private :first, :second
      end
      result = action.run
      expect(seen).to eq([false, :second_ran])
      expect(result).to be_a(Actionable::Failure)
      expect([result.code, result.message]).to eq([:adrift, 'no way'])
      expect(result.errors.to_h).to eq(name: ['bad'], tags: %w[x y])
    end

    it 'AC-B#plainverbs: skip records a Skipped with a default code and returns false' do
      action = build_action do
        step :sail
        define_method(:sail) { skip }
        private :sail
      end
      result = action.run
      expect(result).to be_a(Actionable::Skipped)
      expect(result.code).to eq(:skipped)
    end

    it 'AC-B#plainverbs: skip takes a code, message and output' do
      action = build_action do
        step :sail
        define_method(:sail) { skip(:dup, 'seen', existing_id: 42) }
        private :sail
      end
      result = action.run
      expect([result.code, result.message, result.output]).to eq([:dup, 'seen', { existing_id: 42 }])
    end

    it 'AC-B#lastwins: the most recent record wins' do
      action = build_action do
        step :one
        step :two
        define_method(:one) { fail(:adrift) }
        define_method(:two) { succeed('recovered') }
        private :one, :two
      end
      result = action.run
      expect(result).to be_a(Actionable::Success)
      expect(result.message).to eq('recovered')
    end

    it 'AC-B#lastwins: with no record the run auto-succeeds' do
      action = build_action do
        step :noop
        define_method(:noop) { @x = 1 }
        private :noop
      end
      result = action.run
      expect(result).to be_a(Actionable::Success)
      expect(result.code).to eq(:success)
    end

    it 'AC-B#failerrors: every keyword after the message is an error, none reserved for metadata' do
      action = build_action do
        step :sail
        define_method(:sail) { fail!(:x, nil, kind: 'is not valid') }
        private :sail
      end
      expect(action.run.errors[:kind]).to eq(['is not valid'])
    end

    it 'AC-B#failerrors: String-keyed errors are stored under their Symbol key' do
      action = build_action do
        step :sail
        define_method(:sail) { fail(:x, nil, **{ 'name' => 'bad' }) }
        private :sail
      end
      expect(action.run.errors.to_h).to eq(name: ['bad'])
    end
  end

  describe 'bang verbs' do
    it 'AC-B#bangverbs: record and halt, so remaining main steps are skipped' do
      ran = []
      action = build_action do
        step :one
        step :two
        define_method(:one) { fail!(:stop, 'halted') }
        define_method(:two) { ran << :two }
        private :one, :two
      end
      result = action.run
      expect(ran).to be_empty
      expect(result.code).to eq(:stop)
    end

    it 'AC-B#bangverbs: succeed! and skip! halt with their record' do
      ok = build_action do
        step :one
        step :two
        define_method(:one) { succeed!('early', n: 1) }
        define_method(:two) { raise 'unreachable' }
        private :one, :two
      end
      expect(ok.run).to have_attributes(message: 'early', output: { n: 1 })
      skipper = build_action do
        step :one
        define_method(:one) { skip!(:later) }
        private :one
      end
      expect(skipper.run).to be_skipped
    end

    it 'AC-B#bangverbs: halt! alone keeps the current result, and auto-succeeds with none' do
      keeps = build_action do
        step :one
        step :two
        define_method(:one) { fail(:kept) }
        define_method(:two) { halt! }
        step :three
        define_method(:three) { raise 'unreachable' }
        private :one, :two, :three
      end
      expect(keeps.run.code).to eq(:kept)
      bare = build_action do
        step :one
        define_method(:one) { halt! }
        private :one
      end
      expect(bare.run).to be_success
    end

    it 'AC-B#halttag: a bang verb outside a run surfaces UncaughtThrowError' do
      action = build_action
      expect { action.new.send(:halt!) }.to raise_error(UncaughtThrowError)
      expect { action.new.send(:fail!, :x) }.to raise_error(UncaughtThrowError)
    end
  end

  describe 'fail_with' do
    let(:schema) { Class.new(FieldStruct::Base) { required :field, :string } }

    it 'AC-B#failwith: copies the source errors under the default :invalid code' do
      side = schema.new
      action = build_action do
        step :sail
        define_method(:sail) { fail_with!(side) }
        private :sail
      end
      result = action.run
      expect(result).to be_a(Actionable::Failure)
      expect([result.code, result.errors[:field]]).to eq([:invalid, ['is required']])
    end

    it 'AC-B#failwith: takes a code and message; the plain form returns false and continues' do
      side = schema.new
      seen = []
      action = build_action do
        step :sail
        define_method(:sail) { seen << fail_with(side, code: :bad, message: 'adrift') }
        private :sail
      end
      result = action.run
      expect(seen).to eq([false])
      expect([result.code, result.message]).to eq([:bad, 'adrift'])
    end

    it 'AC-B#failwith: output: is refused without a schema or typed outcomes' do
      side = schema.new
      action = build_action do
        step :sail
        define_method(:sail) { fail_with!(side, output: { a: 1 }) }
        private :sail
      end
      expect do
        action.run
      end.to raise_error(ArgumentError,
                         /fail_with takes output: only under typed_outcomes or for a code that declares an output schema/)
    end
  end

  describe 'identifier codes' do
    def run_with(&body)
      action = build_action do
        step :sail
        define_method(:sail, &body)
        private :sail
      end
      action.run
    end

    it 'AC-B#codeformat: accepts identifiers, stores Symbols' do
      expect(run_with { fail(:deck_full) }.code).to eq(:deck_full)
      expect(run_with { fail(:ok?) }.code).to eq(:ok?)
      expect(run_with { fail('NotFound') }.code).to eq(:NotFound)
      expect(run_with { skip('kraken') }.code).to eq(:kraken)
    end

    it 'AC-B#codeformat: rejects sentences, dashes, digits, nil and classes with the documented message' do
      ['a sentence', 'a-b', 'a.b', '1abc', '', nil, String, 5].each do |bad|
        error = begin
          run_with { fail(bad) }
          nil
        rescue ArgumentError => e
          e
        end
        expect(error).to be_a(ArgumentError), "expected #{bad.inspect} to be refused"
        expect(error.message).to include('action', 'failure', bad.inspect, 'is not an identifier', 'Kernel#fail', 'use raise')
      end
      expect { run_with { skip('a sentence') } }.to raise_error(ArgumentError, /action: skip code "a sentence" is not an identifier/)
    end

    it 'AC-B#codeformat: names the action when it has a name, and every verb checks' do
      named_action('Probe') do
        step :sail
        define_method(:sail) { fail!('two words') }
        private :sail
      end
      expect { Probe.run }.to raise_error(ArgumentError, /\AProbe: failure code "two words"/)
      %i[fail! fail_with fail_with!].each do |verb|
        action = build_action do
          step :sail
          define_method(:sail) { verb == :fail! ? fail!('x y') : __send__(verb, Actionable::Failure.new, code: 'x y') }
          private :sail
        end
        expect { action.run }.to raise_error(ArgumentError, /is not an identifier/)
      end
    end

    it 'AC-B#codeformat: the verb-position switch does not disable it' do
      original = Actionable.verb_position_check?
      Actionable.verb_position_check = false
      expect { run_with { fail('x y') } }.to raise_error(ArgumentError)
    ensure
      Actionable.verb_position_check = original
    end

    it 'AC-B#failshadow: fail \'kraken\' records code :kraken, a sentence or a class raises ArgumentError' do
      expect(run_with { fail 'kraken' }.code).to eq(:kraken)
      expect { run_with { fail 'some sentence' } }.to raise_error(ArgumentError)
      expect { run_with { fail RuntimeError, 'msg' } }.to raise_error(ArgumentError)
    end

    it 'AC-B#failshadow: code outside the action still gets Kernel#fail' do
      helper = Class.new { def blow = fail('real error') }
      expect { helper.new.blow }.to raise_error(RuntimeError, 'real error')
    end
  end

  it 'AC-B#verbsprivate: verbs are private; result is a public reader' do
    action = build_action
    %i[succeed succeed! fail fail! fail_with fail_with! skip skip! halt!].each do |verb|
      expect { action.new.public_send(verb) }.to raise_error(NoMethodError)
    end
    expect(action.new).to respond_to(:result)
    expect(action.new.result).to be_nil
  end

  it 'AC-I2: genuine exceptions propagate untouched' do
    action = build_action do
      step :sail
      define_method(:sail) { raise KeyError, 'inside' }
      private :sail
    end
    expect { action.run }.to raise_error(KeyError, 'inside')
  end
end
