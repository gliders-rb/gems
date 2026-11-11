# frozen_string_literal: true

module Actionable
  # Class-level +typed_outcomes+: per-action result classes, and the rebuild of a run's result into them.
  module TypedOutcomes
    # The constant each outcome gets inside a typed action, and the gem class it subclasses.
    #
    # @return [Hash{Symbol=>Array(Symbol, Class)}]
    OUTCOME_CLASSES = { success: [:Success, Success], failure: [:Failure, Failure], skipped: [:Skipped, Skipped] }.freeze

    # Turns typed outcomes on or off for this class (inherited by subclasses at creation).
    #
    # @param enabled [Boolean]
    # @return [Boolean] the new setting
    # @raise [Actionable::DefinitionError] when the action already has its own +Success+, +Failure+ or +Skipped+
    def typed_outcomes(enabled: true)
      define_result_classes if enabled
      @typed_outcomes = enabled ? true : false
    end

    # @return [Boolean] whether this action returns its own result classes
    def typed_outcomes?
      @typed_outcomes ? true : false
    end

    # @param outcome [Symbol] +:success+, +:failure+ or +:skipped+
    # @return [Class, nil] this action's own class for the outcome
    def typed_result_class(outcome)
      @typed_result_classes&.fetch(outcome, nil)
    end

    # Defines the own result classes, each a subclass of the parent action's own class when it has them.
    #
    # @return [void]
    def define_result_classes
      @typed_result_classes ||= {}
      pending = OUTCOME_CLASSES.reject { |outcome, _| @typed_result_classes.key?(outcome) }
      pending.each_value do |(const, _)|
        next unless const_defined?(const, false)

        raise DefinitionError, "#{Actionable.label_for(self)} has its own #{const}, which typed outcomes would replace; rename it"
      end
      pending.each { |outcome, (const, gem_class)| @typed_result_classes[outcome] = new_result_class(const, outcome, gem_class) }
    end

    # Fits +result+ to this action's own class for its outcome: a result of that class, or of a host's own subclass,
    # is returned as is; a gem result or another action's own result is rebuilt with the same attributes and errors.
    #
    # @param result [Actionable::Result]
    # @return [Actionable::Result]
    def own_result(result)
      return result unless typed_outcomes?

      target = typed_result_class(outcome_of(result))
      return result if target.nil? || result.instance_of?(target) || !rebuildable?(result.class)

      rebuild_result(result, target)
    end

    private

    def new_result_class(const, outcome, gem_class)
      parent = superclass.respond_to?(:typed_outcomes?) && superclass.typed_outcomes? ? superclass.typed_result_class(outcome) : nil
      klass = Class.new(parent || gem_class)
      klass.instance_variable_set(:@actionable_owner, self)
      const_set(const, klass)
      klass
    end

    def outcome_of(result)
      return :success if result.success?
      return :skipped if result.skipped?

      :failure if result.failure?
    end

    def rebuildable?(klass)
      klass.generated? || OUTCOME_CLASSES.each_value.any? { |(_, gem_class)| gem_class == klass }
    end

    def rebuild_result(result, target)
      attributes = result.class.attribute_names.to_h { |name| [name, result.public_send(name)] }
      rebuilt = target.new(**attributes)
      rebuilt.output_fields_set = result.output_fields_set
      copy_errors(result, rebuilt)
    end

    # The rebuild must carry exactly the source's errors: whatever construction added is removed first.
    def copy_errors(source, rebuilt)
      rebuilt.errors.to_h.each_key { |field| rebuilt.errors.clear(field) }
      rebuilt.absorb_errors_from(source)
    end
  end
end
