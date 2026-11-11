# frozen_string_literal: true

module Actionable
  # Fiber-local measurement state: whether a measuring run is active here, and the history entry currently open.
  module Measurement
    SLOT = :actionable_measurement
    # What a fiber with no run in progress, or a non-measuring run, sees (shared, never mutated).
    IDLE = { active: false, open: nil }.freeze
    private_constant :SLOT, :IDLE

    class << self
      # @return [Boolean] whether a measuring run is active on this fiber
      def recording?
        current[:active]
      end

      # @return [Actionable::History::Step, nil] the entry of the step or hook now running
      def current_entry
        current[:open]
      end

      # Runs the block as one run: state is saved first and restored afterwards.
      #
      # @param active [Boolean] whether this run measures
      # @return [Object] the block value
      def around_run(active:, &block)
        install(active ? { active: true, open: nil } : IDLE, &block)
      end

      # Runs the block with +entry+ as the open entry.
      #
      # @param entry [Actionable::History::Step]
      # @return [Object] the block value
      def around_entry(entry, &block)
        state = Thread.current[SLOT]
        return install({ active: true, open: entry }, &block) unless state&.fetch(:active) && !state.frozen?

        outer = state[:open]
        state[:open] = entry
        begin
          yield
        ensure
          state[:open] = outer
        end
      end

      # Attaches a finished child run's history to the open entry (the action step or hook that ran it).
      #
      # @param history [Object] a {History}, anything else is ignored
      # @return [void]
      def adopt_child_history(history)
        return unless history.is_a?(History)

        entry = current_entry
        entry.nested = history if entry
      end

      private

      def current
        Thread.current[SLOT] || IDLE
      end

      def install(replacement)
        saved = Thread.current[SLOT]
        Thread.current[SLOT] = replacement
        yield
      ensure
        Thread.current[SLOT] = saved
      end
    end
  end
end
