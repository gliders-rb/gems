# frozen_string_literal: true

require 'actionable/rspec'

RSpec.describe 'perform_actionable' do
  let(:bosun) do
    named_action('MatcherBosun') do
      define_method(:initialize) do |name = nil, mode: :ok|
        @name = name
        @mode = mode
      end
      step :sail

      private

      def sail
        case @mode
        when :fail then fail!(:adrift, 'cannot greet')
        when :skip then skip!(:later, 'not yet')
        when :kraken then raise ArgumentError, 'kraken'
        else succeed("ahoy #{@name}")
        end
      end
    end
  end

  describe 'matching (AC-B#matcher, AC-B#matchsemantics)' do
    it 'is included into example groups when RSpec is defined (AC-B#rspecload)' do
      expect(self).to be_a(Actionable::RSpec::Matchers)
      expect(self).to be_a(Actionable::RSpec::Stubs)
    end

    it 'bare perform_actionable expects success and forwards positional and keyword arguments' do
      expect(bosun).to perform_actionable('Marlow')
      expect(bosun).to perform_actionable('Marlow').and_succeed('ahoy Marlow')
      expect(bosun).not_to perform_actionable(mode: :fail)
    end

    it 'matches messages with ===, so strings, regexps and classes work; nil does not check' do
      expect(bosun).to perform_actionable('Marlow').and_succeed(/Marlow/)
      expect(bosun).to perform_actionable('Marlow').and_succeed(String)
      expect(bosun).not_to perform_actionable('Marlow').and_succeed('other')
      expect(bosun).to perform_actionable(mode: :fail).and_fail(:adrift, 'cannot greet')
      expect(bosun).to perform_actionable(mode: :fail).and_fail(:adrift, /cannot/)
      expect(bosun).to perform_actionable(mode: :fail).and_fail
      expect(bosun).not_to perform_actionable(mode: :fail).and_fail(:other)
    end

    it 'treats a skip as neither a success nor a failure' do
      expect(bosun).to perform_actionable(mode: :skip).and_skip(:later, 'not yet')
      expect(bosun).to perform_actionable(mode: :skip).and_skip
      expect(bosun).not_to perform_actionable(mode: :skip).and_succeed
      expect(bosun).not_to perform_actionable(mode: :skip).and_fail
      expect(bosun).not_to perform_actionable(mode: :fail).and_skip
    end

    it 'and_raise captures a StandardError and matches its class and message' do
      expect(bosun).to perform_actionable(mode: :kraken).and_raise
      expect(bosun).to perform_actionable(mode: :kraken).and_raise(ArgumentError)
      expect(bosun).to perform_actionable(mode: :kraken).and_raise(ArgumentError, /kraken/)
      expect(bosun).not_to perform_actionable(mode: :kraken).and_raise(KeyError)
      expect(bosun).not_to perform_actionable(mode: :kraken).and_raise(ArgumentError, 'other')
      expect(bosun).not_to perform_actionable('Marlow').and_raise
      expect(bosun).not_to perform_actionable(mode: :kraken).and_succeed
    end

    it 'the last chain wins the outcome' do
      expect(bosun).to perform_actionable(mode: :fail).and_succeed.and_fail(:adrift)
      expect(bosun).to perform_actionable('Marlow').and_fail.and_succeed
    end

    it 'calls the block with (result, exception) after the primary match; it must be truthy' do
      seen = nil
      expect(bosun).to(perform_actionable('Marlow').and_succeed { |result, exception| seen = [result.message, exception] })
      expect(seen).to eq(['ahoy Marlow', nil])
      matcher = perform_actionable('Marlow').and_succeed { |_result, _exception| false }
      expect(matcher.matches?(bosun)).to be(false)
      raised = nil
      expect(bosun).to(perform_actionable(mode: :kraken).and_raise { |result, exception| raised = [result, exception.message] })
      expect(raised).to eq([nil, 'kraken'])
    end

    it 'takes the block given to perform_actionable itself' do
      calls = []
      expect(bosun).to(perform_actionable('Marlow') { |result, _| calls << result.code })
      expect(calls).to eq([:success])
    end

    it 'AC-B#matchneg: negation covers the primary match only, so the block is ignored' do
      called = false
      expect(bosun).not_to(perform_actionable(mode: :fail).and_succeed { called = true })
      expect(called).to be(false)
    end

    it 'does not capture an Exception that is not a StandardError' do
      klass = build_action do
        step :sail
        define_method(:sail) { raise Interrupt }
      end
      expect { klass.run }.to raise_error(Interrupt)
      matcher = perform_actionable.and_succeed
      expect { matcher.matches?(klass) }.to raise_error(Interrupt)
    end
  end

  describe 'declared codes (AC-B#matchdeclared)' do
    let(:declared) do
      build_action do
        fails :a
        fails :b
        skips :c
        step :sail
        define_method(:sail) { nil }
      end
    end

    it 'raises ArgumentError for an undeclared Symbol code, even when negated' do
      message = 'action does not declare :ebb (declared: :a, :b); a stub or and_fail with it tests a failure the action can never return'
      expect { expect(declared).to perform_actionable.and_fail(:ebb) }.to raise_error(ArgumentError, message)
      expect { expect(declared).not_to perform_actionable.and_fail(:ebb) }.to raise_error(ArgumentError, message)
      skip_message = 'action does not declare skip :ebb (declared: :c); a stub or and_skip with it tests a skip the action can never return'
      expect { expect(declared).to perform_actionable.and_skip(:ebb) }.to raise_error(ArgumentError, skip_message)
    end

    it 'names the action when it has a name' do
      klass = named_action('MatcherNamed') do
        fails :a
        step :sail
        define_method(:sail) { nil }
      end
      expect { expect(klass).to perform_actionable.and_fail(:ebb) }.to raise_error(ArgumentError, /\AMatcherNamed does not declare :ebb/)
    end

    it 'allows declared codes, gem codes, a bare and_fail/and_skip, and any code when nothing is declared' do
      expect(declared).not_to perform_actionable.and_fail(:a)
      expect(declared).not_to perform_actionable.and_fail(:invalid_input)
      expect(declared).not_to perform_actionable.and_fail
      expect(declared).not_to perform_actionable.and_skip
      expect(declared).not_to perform_actionable.and_skip(:c)
      expect(bosun).not_to perform_actionable.and_fail(:anything)
    end
  end

  describe 'messages (AC-B#matchmessages)' do
    def failing(action, matcher)
      matcher.matches?(action)
      matcher
    end

    it 'describes a result mismatch' do
      matcher = failing(bosun, perform_actionable(mode: :fail).and_succeed('hi'))
      result = bosun.run(mode: :fail)
      expect(matcher.failure_message).to eq("expected MatcherBosun to succeed with message \"hi\", but got #{result.inspect}")
    end

    it 'includes the code and message for fail and skip' do
      matcher = failing(bosun, perform_actionable.and_fail(:adrift, 'x'))
      expect(matcher.failure_message).to start_with('expected MatcherBosun to fail with code :adrift with message "x", but got ')
      matcher = failing(bosun, perform_actionable.and_skip(:later))
      expect(matcher.failure_message).to start_with('expected MatcherBosun to skip with code :later, but got ')
    end

    it 'shows the exception and its backtrace when the run raised' do
      matcher = failing(bosun, perform_actionable(mode: :kraken).and_succeed)
      lines = matcher.failure_message.lines
      expect(lines.first).to eq("expected MatcherBosun to succeed, but it raised ArgumentError: kraken\n")
      expect(lines.size).to be > 2
    end

    it 'says what was expected when a raise did not happen, and when nothing ran' do
      matcher = failing(bosun, perform_actionable('Marlow').and_raise(KeyError))
      expect(matcher.failure_message).to start_with('expected MatcherBosun to raise KeyError, but got ')
      expect(perform_actionable.and_fail.failure_message).to eq('expected nil to fail, but no result was produced')
    end

    it 'AC-B#matchbacktrace: shortens the backtrace to ACTIONABLE_BACKTRACE_QTY frames (default 10) when asked' do
      matcher = failing(bosun, perform_actionable(mode: :kraken).and_succeed)
      full = matcher.failure_message.lines.size - 1
      stub_const('ENV', ENV.to_h.merge('ACTIONABLE_SHORT_BACKTRACE' => '1'))
      expect(matcher.failure_message.lines.size - 1).to eq([full, 10].min)
      stub_const('ENV', ENV.to_h.merge('ACTIONABLE_SHORT_BACKTRACE' => '1', 'ACTIONABLE_BACKTRACE_QTY' => '2'))
      expect(matcher.failure_message.lines.size - 1).to eq(2)
    end

    it 'has a negated message and a description' do
      matcher = perform_actionable('Marlow').and_succeed
      matcher.matches?(bosun)
      expect(matcher.failure_message_when_negated).to eq('expected MatcherBosun not to succeed, but it did')
      expect(matcher.description).to eq('perform actionable and succeed')
      expect(perform_actionable.and_raise(KeyError, /x/).tap { |m| m.matches?(bosun) }.failure_message_when_negated)
        .to eq('expected MatcherBosun not to raise KeyError with message /x/, but it did')
    end
  end
end
