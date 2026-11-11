# frozen_string_literal: true

require_relative '../actionable'

module Actionable
  # RSpec support: the +perform_actionable+ matcher and the stub helpers. Inside +module Actionable+ the name +RSpec+
  # means this module; reach the framework as +::RSpec+.
  module RSpec
    # How each outcome kind is checked and worded in a broken-spec message.
    #
    # @return [Hash{Symbol=>Hash{Symbol=>String, Symbol}}]
    KINDS = {
      failure: { allows: :allows_failure_code?, declared: :declared_failures, word: '', chain: 'fail', noun: 'failure' },
      skip: { allows: :allows_skip_code?, declared: :declared_skips, word: 'skip ', chain: 'skip', noun: 'skip' }
    }.freeze

    class << self
      # Fails a spec that names a code the action can never produce (AC-B#matchdeclared).
      #
      # @param action [Class]
      # @param kind [Symbol] +:failure+ or +:skip+
      # @param code [Symbol]
      # @return [void]
      # @raise [ArgumentError]
      def check_declared!(action, kind, code)
        info = KINDS.fetch(kind)
        return if action.public_send(info[:allows], code)

        declared = action.public_send(info[:declared]).keys.map(&:inspect).join(', ')
        raise ArgumentError, "#{Actionable.label_for(action)} does not declare #{info[:word]}#{code.inspect} " \
                             "(declared: #{declared}); a stub or and_#{info[:chain]} with it tests " \
                             "a #{info[:noun]} the action can never return"
      end

      # Tells outcome coverage (when loaded) that a stub answered a call of +action.run+.
      #
      # @param action [Class]
      # @param result [Actionable::Result]
      # @return [void]
      def note_stub(action, result)
        return unless defined?(Actionable::Coverage) && Actionable::Coverage.respond_to?(:record_stub)

        Actionable::Coverage.record_stub(action.name, result.status, result.code)
      end
    end

    # The matcher factory included into example groups.
    module Matchers
      # @param args [Object] positional run arguments
      # @param kwargs [Object] keyword run arguments
      # @yield [result, exception] checked after the primary match
      # @return [Actionable::RSpec::PerformActionable]
      def perform_actionable(*args, **kwargs, &block)
        PerformActionable.new(args, kwargs, &block)
      end
    end
  end
end

require_relative 'rspec/perform_actionable'
require_relative 'rspec/results'
require_relative 'rspec/stubs'

if defined?(RSpec) && RSpec.respond_to?(:configure)
  RSpec.configure do |config|
    config.include Actionable::RSpec::Matchers
    config.include Actionable::RSpec::Stubs
  end
end
