# frozen_string_literal: true

require 'opentelemetry'
require 'actionable'
require_relative 'otel/version'

# The actionable-rb namespace; this gem adds {Otel}.
module Actionable
  # OpenTelemetry tracing for actionable: a run span per `Action.run`, a step span per executed step and hook.
  # Requiring `actionable/otel` turns it on. Spans carry class, step and section names, outcomes and result
  # codes, never an input or output value.
  module Otel
    # The instrumentation scope name of the tracer.
    # @return [String]
    TRACER_NAME = 'actionable'

    # The values `exception_details=` accepts.
    # @return [Array<Symbol>]
    EXCEPTION_DETAILS = %i[type_only full].freeze

    # What a permanent class name looks like: a constant path.
    PERMANENT_NAME = /\A[[:upper:]][[:alnum:]_]*(?:::[[:upper:]][[:alnum:]_]*)*\z/
    private_constant :PERMANENT_NAME

    @exception_details = :type_only
    @step_spans = true
    @tracer_pair = nil
    @step_cache = ObjectSpace::WeakKeyMap.new

    # What a step span needs that does not change between runs: its name and the attribute values that are fixed for
    # one (action label, step, section). The SDK keeps and mutates the Hash it is given, so each span gets a copy.
    # +target+ is the label of an action step's class when it was built (nil for other steps).
    StepSpan = Struct.new(:name, :attributes, :target)
    private_constant :StepSpan

    class << self
      # @return [Symbol] `:type_only` (default) or `:full`
      attr_reader :exception_details

      # Sets how much of an escaping exception the run span records.
      #
      # @param level [Symbol] `:type_only` or `:full`
      # @return [Symbol]
      # @raise [ArgumentError] for anything else
      def exception_details=(level)
        unless EXCEPTION_DETAILS.include?(level)
          raise ArgumentError,
                "Actionable::Otel.exception_details must be #{EXCEPTION_DETAILS.map(&:inspect).join(' or ')}, got #{level.inspect}"
        end

        @exception_details = level
      end

      # @return [Boolean] whether step and hook spans are emitted (default true)
      def step_spans? = @step_spans

      # Turns step spans on (truthy) or off (`false`/`nil`).
      #
      # @param enabled [Object]
      # @return [Object] the argument
      def step_spans=(enabled)
        @step_spans = enabled ? true : false
        enabled
      end

      # The tracer of the current provider, cached together with that provider as one frozen pair.
      #
      # @return [Object] an OpenTelemetry tracer
      def tracer
        provider = OpenTelemetry.tracer_provider
        pair = @tracer_pair
        return pair[1] if pair && pair[0].equal?(provider)

        tracer = provider.tracer(TRACER_NAME, VERSION)
        @tracer_pair = [provider, tracer].freeze
        tracer
      end

      # Runs the block inside the run span of one `Action.run` and annotates the span with the result.
      #
      # @param action [Class] the action class being run
      # @yieldreturn [Actionable::Result] the result of the run
      # @return [Actionable::Result] the block's result, unchanged
      def trace_run(action, &block)
        label = label_for(action)
        name = temporary_name?(action) ? "#{label}.run" : run_name(label)
        tracer.in_span(name, attributes: { 'actionable.action' => label }, kind: :internal,
                             record_exception: false) do |span|
          outcome = run_recording(span, &block)
          annotate_run(span, outcome)
          outcome
        end
      end

      # Runs the block inside the span of one executed step or hook (one call of the runner's `record` seam).
      #
      # @param instance [Actionable::Action] the action instance being run
      # @param section [Symbol] `:main`, `:success`, `:failure`, `:skip` or `:always`
      # @param step [Object] the step object (`name`, `kind`)
      # @yieldreturn [Object] the step's value
      # @return [Object] the block's value
      def trace_step(instance, section, step, &block)
        return yield unless step_spans?

        label = label_for(instance.class)
        klass = instance.class
        prepared = temporary_name?(klass) ? build_step_span(label, section, step) : step_span(label, section, step)
        tracer.in_span(prepared.name, attributes: prepared.attributes.dup, kind: :internal, record_exception: false) do |span|
          step_recording(instance, span, &block)
        end
      end

      # The span label of an action class: its name, or `Actionable::Action` when anonymous.
      #
      # @param klass [Class]
      # @return [String]
      def label_for(klass) = klass.name || Actionable::Action.name

      private

      # A class whose name is temporary (anonymous, or set with `set_temporary_name`) has no constant behind its
      # name. A temporary name can never be a valid constant path, so one that is not is temporary. OT-B9.
      def temporary_name?(klass)
        name = klass.name
        name.nil? || !name.match?(PERMANENT_NAME)
      end

      # The run span's name per label; a label is a class name, so the table stays as small as the set of actions.
      def run_name(label)
        (@run_names ||= {})[label] ||= "#{label}.run".freeze
      end

      # The prepared span of a step in a section, built once per (step, action label, section). The label is part of
      # the key because a subclass shares its parent's steps, and a class can be named after its first run; for the
      # same reason an action step's span is rebuilt when its class's label is no longer the one it was built with.
      def step_span(label, section, step)
        by_label = (@step_cache[step] ||= {}.compare_by_identity)
        by_section = (by_label[label] ||= {})
        prepared = by_section[section]
        return prepared if prepared && (prepared.target.nil? || prepared.target == label_for(step.name))

        by_section[section] = build_step_span(label, section, step)
      end

      def build_step_span(label, section, step)
        name = step.name
        target = label_for(name) if name.is_a?(Class)
        step_name = (target || name.to_s).dup.freeze
        attributes = {
          'actionable.action' => label,
          'actionable.step' => step_name,
          'actionable.step.kind' => step.kind.to_s.freeze,
          'actionable.section' => section.to_s.freeze
        }.freeze
        StepSpan.new("#{label}/#{step_name}".freeze, attributes, target)
      end

      # A halt is a throw, so the code is set from an ensure: a halting step still carries its code.
      def step_recording(instance, span)
        seen = instance.result
        yield
      ensure
        current = instance.result
        changed = !current.equal?(seen) && current.is_a?(Actionable::Result)
        span.set_attribute('actionable.code', current.code.to_s) if changed
      end

      def run_recording(span)
        yield
      rescue Exception => e # rubocop:disable Lint/RescueException -- recorded, then re-raised unchanged
        record_error(span, e)
        raise
      end

      def record_error(span, error)
        return span.record_exception(error) if @exception_details == :full

        type = error.class.name || error.class.to_s
        span.add_event('exception', attributes: { 'exception.type' => type })
      end

      def annotate_run(span, result)
        code = result.code.to_s
        span.set_attribute('actionable.outcome', result.status.to_s)
        span.set_attribute('actionable.code', code)
        return unless result.failure?

        span.status = OpenTelemetry::Trace::Status.error(code)
      end
    end

    # Prepended onto `Actionable::Action`'s singleton class: wraps `.run` in the run span.
    module ActionRun
      # @param args [Array<Object>] positional run arguments, forwarded verbatim
      # @param kwargs [Object] keyword run arguments, forwarded verbatim
      # @return [Actionable::Result]
      def run(*args, **kwargs)
        Otel.trace_run(self) { super(*args, **kwargs) }
      end
    end

    # Prepended onto `Actionable::Runner`: wraps its private `record(section, step)` seam in the step span.
    module RunnerSteps
      private

      # @param section [Symbol]
      # @param step [Object]
      # @return [Object] the block's value
      def record(section, step, &inner)
        Otel.trace_step(@instance, section, step) { super(section, step, &inner) }
      end
    end

    Actionable::Action.singleton_class.send(:prepend, ActionRun)
    Actionable::Runner.send(:prepend, RunnerSteps) # rubocop:disable Lint/SendWithMixinArgument -- plain prepend makes YARD list a bogus mixin
  end
end
