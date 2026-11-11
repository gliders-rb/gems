# frozen_string_literal: true

module Actionable
  module RSpec
    # The matcher behind +perform_actionable+: runs an action class and judges its outcome (or the exception it raised).
    #
    # @example
    #   expect(CreateBook).to perform_actionable(title: 'x').and_succeed
    #   expect(CreateBook).to perform_actionable(title: '').and_fail(:invalid_input)
    class PerformActionable
      # What each chain expects, as the phrase used in failure messages.
      #
      # @return [Hash{Symbol=>String}]
      PHRASES = { succeed: 'succeed', fail: 'fail', skip: 'skip', raise: 'raise' }.freeze

      # @param args [Object] positional run arguments
      # @param kwargs [Object] keyword run arguments
      # @yield [result, exception] checked after the primary match; must return truthy
      def initialize(args, kwargs, &block)
        @args = args
        @kwargs = kwargs
        @block = block
        @outcome = :succeed
        @code = @message = nil
        @error_class = StandardError
      end

      # Expects a success, optionally with a message matched by +===+.
      #
      # @param message [Object, nil]
      # @return [self]
      def and_succeed(message = nil, &block)
        expect_outcome(:succeed, nil, message, block)
      end

      # Expects a failure, optionally with a code (compared by +==+) and a message.
      #
      # @param code [Symbol, nil]
      # @param message [Object, nil]
      # @return [self]
      def and_fail(code = nil, message = nil, &block)
        expect_outcome(:fail, code, message, block)
      end

      # Expects a skip, optionally with a code and a message.
      #
      # @param code [Symbol, nil]
      # @param message [Object, nil]
      # @return [self]
      def and_skip(code = nil, message = nil, &block)
        expect_outcome(:skip, code, message, block)
      end

      # Expects the run to raise.
      #
      # @param error_class [Class]
      # @param message [Object, nil]
      # @return [self]
      def and_raise(error_class = StandardError, message = nil, &block)
        @error_class = error_class
        expect_outcome(:raise, nil, message, block)
      end

      # @param action [Class] an action class
      # @return [Boolean]
      def matches?(action, &block)
        @block ||= block
        run(action)
        primary_match? && block_passes?
      end

      # The negation of the primary match only; the block is ignored.
      #
      # @param action [Class]
      # @return [Boolean]
      def does_not_match?(action) # rubocop:disable Naming/PredicatePrefix
        run(action)
        !primary_match?
      end

      # @return [String]
      def failure_message
        "expected #{@action.inspect} to #{phrase}, but #{actual}"
      end

      # @return [String]
      def failure_message_when_negated
        "expected #{@action.inspect} not to #{phrase}, but it did"
      end

      # @return [String]
      def description
        "perform actionable and #{@outcome}"
      end

      private

      def expect_outcome(outcome, code, message, block)
        @outcome = outcome
        @code = code
        @message = message
        @block = block if block
        self
      end

      # Runs the action, capturing a StandardError instead of raising it. A broken spec (an undeclared code) raises.
      def run(action)
        @action = action
        @result = @exception = nil
        check_declared!(action)
        @result = action.run(*@args, **@kwargs)
      rescue StandardError => e
        raise if e.equal?(@broken_spec)

        @exception = e
      end

      def check_declared!(action)
        kind = { fail: :failure, skip: :skip }[@outcome]
        return unless kind && @code.is_a?(Symbol) && action.respond_to?(:allows_failure_code?)

        RSpec.check_declared!(action, kind, @code)
      rescue ArgumentError => e
        @broken_spec = e
        raise
      end

      def primary_match?
        return false unless @exception.nil? == (@outcome != :raise)

        send(:"#{@outcome}_match?")
      end

      def succeed_match? = @result.success? && message_matches?(@result.message)

      def fail_match? = @result.failure? && result_matches?

      def skip_match? = @result.skipped? && result_matches?

      def raise_match? = raised_match?

      def raised_match?
        @exception.is_a?(@error_class) && message_matches?(@exception.message)
      end

      def result_matches?
        (@code.nil? || @result.code == @code) && message_matches?(@result.message)
      end

      def message_matches?(actual)
        @message.nil? || @message === actual # rubocop:disable Style/CaseEquality
      end

      def block_passes?
        @block.nil? || @block.call(@result, @exception) ? true : false
      end

      def phrase
        text = PHRASES.fetch(@outcome)
        text = "raise #{@error_class}" if @outcome == :raise
        text += " with code #{@code.inspect}" if @code && %i[fail skip].include?(@outcome)
        text += " with message #{@message.inspect}" if @message
        text
      end

      def actual
        return "got #{@result.inspect}" if @result
        return "it raised #{@exception.class}: #{@exception.message}\n#{backtrace.join("\n")}" if @exception

        'no result was produced'
      end

      def backtrace
        frames = @exception.backtrace || []
        return frames unless ENV.key?('ACTIONABLE_SHORT_BACKTRACE')

        frames.first(ENV.fetch('ACTIONABLE_BACKTRACE_QTY', '10').to_i)
      end
    end
  end
end
