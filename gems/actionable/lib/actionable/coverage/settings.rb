# frozen_string_literal: true

module Actionable
  module Coverage
    # Hint printed before new gaps in a baseline mismatch.
    #
    # @return [String]
    DEFAULT_NEW_GAP_HINT = 'Write a spec that reaches each one, or add it to the baseline:'
    # Failure codes the gem emits itself, the only ones +gem_codes+ accepts.
    #
    # @return [Array<Symbol>]
    GEM_CODES = Action::GEM_FAILURE_CODES

    # Module-level settings; {#reset_config!} restores every default.
    module Settings
      # @return [Class] where the walk for actions starts (default +Actionable::Action+)
      def root = @root || Action

      # @return [Array<String, Regexp>]
      def include_prefixes = (@include_prefixes ||= [])

      # @return [Array<String, Regexp>]
      def exclude_prefixes = (@exclude_prefixes ||= [])

      # @return [Proc, Method, nil] called before listing actions (for example an eager load)
      attr_accessor :loader

      # @return [String, nil] path of the baseline file
      attr_accessor :baseline

      # @param value [Class, nil] where the walk for actions starts
      # @return [Class, nil]
      attr_writer :root

      # @param value [Array<String, Regexp>]
      # @return [Array<String, Regexp>]
      attr_writer :include_prefixes

      # @param value [Array<String, Regexp>]
      # @return [Array<String, Regexp>]
      attr_writer :exclude_prefixes

      # @param value [String, nil]
      # @return [String, nil]
      attr_writer :new_gap_hint

      # @param value [Boolean]
      # @return [Boolean]
      attr_writer :only_observed

      # @return [Array<Symbol>] gem failure codes to expect where they apply
      def gem_codes = (@gem_codes ||= [])

      # @param codes [Array<Symbol, String>]
      # @return [Array<Symbol>]
      # @raise [ArgumentError] for a code the gem does not emit
      def gem_codes=(codes)
        symbols = Array(codes).map(&:to_sym)
        bad = symbols.find { |code| !GEM_CODES.include?(code) }
        raise ArgumentError, "not a gem failure code: #{bad.inspect} (the gem emits :invalid_input, :invalid_output)" if bad

        @gem_codes = symbols
      end

      # @return [String]
      def new_gap_hint = @new_gap_hint || DEFAULT_NEW_GAP_HINT

      # @return [Boolean] drop actions that had no real run
      def only_observed = @only_observed ? true : false

      # Restores every setting to its default.
      #
      # @return [void]
      def reset_config!
        @root = @loader = @baseline = @new_gap_hint = nil
        @include_prefixes = []
        @exclude_prefixes = []
        @gem_codes = []
        @only_observed = false
      end
    end
  end
end
