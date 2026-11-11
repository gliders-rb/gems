# frozen_string_literal: true

module Actionable
  module Steps
    # Reads a value from a method and runs the first matching branch's target.
    class Case < Base
      # The block of +case_step+: collects branches and the default.
      class Builder
        # @return [Array<Array(Object, Steps::Base)>] +[match_value, step]+ in declaration order
        attr_reader :branches

        # @return [Steps::Base, nil]
        attr_reader :default_step

        def initialize
          @branches = []
          @default_step = nil
        end

        # @param match_value [Object] matched with {ValueMatch.matches?}
        # @param target [Symbol, String, Class] a method name or an action class
        # @param options [Object] +if:+ / +unless:+ and action step options
        # @return [void]
        def on(match_value, target, **options)
          built = Steps.build(target, **options)
          @branches.push([match_value, built])
        end

        # @param target [Symbol, String, Class]
        # @param options [Object]
        # @return [void]
        def default(target, **options)
          @default_step = Steps.build(target, **options)
        end
      end

      # @param value_source [Symbol, String] the method that returns the switch value
      # @param options [Object] guards for the whole step
      # @yield evaluated with a {Builder} as +self+
      # @return [Steps::Case]
      def self.define(value_source, **options, &block)
        collector = Builder.new
        collector.instance_eval(&block) if block
        new(value_source.to_sym, collector.branches, collector.default_step, **options)
      end

      # @return [Array<Array(Object, Steps::Base)>]
      attr_reader :branches

      # @return [Steps::Base, nil]
      attr_reader :default_step

      # @param name [Symbol] the value-source method
      # @param branches [Array<Array(Object, Steps::Base)>]
      # @param default_step [Steps::Base, nil]
      # @param options [Object] +if:+ / +unless:+ for the whole step
      def initialize(name, branches, default_step, **options)
        super(name, **options)
        @branches = branches.freeze
        @default_step = default_step
      end

      # @return [Symbol]
      def kind = :case

      # @return [Array<Symbol>] the value source plus every branch target's methods
      def required_methods
        targets.flat_map(&:required_methods).unshift(name).uniq
      end

      # @return [Array<Steps::Base>] every branch target and the default
      def branch_steps = targets

      # Chooses the branch by value alone; its own guard then decides whether it runs.
      #
      # @param instance [Actionable::Action]
      # @return [Object]
      def call(instance)
        switch_value = instance.__send__(name)
        arm = @branches.detect { |candidate, _| ValueMatch.matches?(candidate, switch_value) }
        picked = arm ? arm[1] : @default_step
        return if picked.nil? || picked.skip?(instance)

        picked.call(instance)
      end

      private

      def targets
        @branches.map { |_, step| step }.push(@default_step).compact
      end
    end
  end
end
