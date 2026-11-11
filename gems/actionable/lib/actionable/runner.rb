# frozen_string_literal: true

module Actionable
  # Internal executor of one run: halts, step records, output refresh and the final result.
  class Runner
    # The schema class ivar caching a schema's instance variable names.
    IVAR_PAIRS = :@__actionable_ivar_pairs
    # The reader of the hook list for each outcome section.
    HOOK_READERS = { success: :success_hooks, failure: :failure_hooks, skip: :skip_hooks }.freeze
    private_constant :IVAR_PAIRS, :HOOK_READERS

    # @param instance [Actionable::Action] the one-run action instance
    def initialize(instance)
      @instance = instance
    end

    # @return [Actionable::Result]
    def run
      @measuring = measuring?
      @history = History.new if @measuring
      Measurement.around_run(active: @measuring) { execute }
    end

    private

    def measuring?
      klass = @instance.class
      Measurement.recording? || klass.measure_all? || klass.measure_sample_hit?
    end

    def execute
      Actionable.catch_halt do
        @instance.class.steps.each { |step| run_step(:main, step) }
      end
      check_result!
      adopt(Success.new) if @instance.result.nil?
      refresh_output
      run_hooks
      finish
    end

    def finish
      result = @instance.result
      result.history = @history if @measuring
      result
    end

    # One outcome category (picked once, from the result now), then the always hooks, each in its own halt catch.
    def run_hooks
      klass = @instance.class
      section = hook_section
      run_phase(section, klass.public_send(HOOK_READERS.fetch(section)))
      run_phase(:always, klass.always_hooks)
    end

    def hook_section
      result = @instance.result
      return :success if result.success?

      result.skipped? ? :skip : :failure
    end

    def run_phase(section, hooks)
      Actionable.catch_halt { hooks.each { |hook| run_hook(section, hook) } }
    end

    # Runs one hook, then checks and re-fits the result; a halting hook re-throws so its phase stops.
    def run_hook(section, hook)
      halted = true
      Actionable.catch_halt do
        run_step(section, hook)
        halted = false
      end
      check_result!
      refresh_output
      throw Actionable::HALT if halted
    end

    def run_step(section, step)
      return if step.skip?(@instance)

      record(section, step) { step.call(@instance) }
      check_result!
    end

    # The single seam an adapter wraps: one call per executed step or hook. When measuring, the default body also
    # appends the history entry (when the block finishes, halts or raises) and returns the block's value.
    def record(section, step, &block)
      return yield unless @measuring

      entry = History::Step.new(section: section, name: step.name, started_at: Time.now, duration: 0.0)
      before = @instance.result
      started = monotonic_now
      begin
        Measurement.around_entry(entry, &block)
      ensure
        close_entry(entry, before, started)
      end
    end

    def close_entry(entry, before, started)
      entry.duration = monotonic_now - started
      after = @instance.result
      entry.code = after.code if !after.equal?(before) && after.is_a?(Result)
      @history << entry
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def adopt(result)
      @instance.instance_variable_set(:@result, result)
    end

    def check_result!
      value = @instance.result
      return if value.nil? || value.is_a?(Result)

      raise DefinitionError, "#{Actionable.label_for(@instance.class)} set @result to a #{value.class}; " \
                             "@result is reserved for the run's result, so rename the instance variable"
    end

    # Fits the current result's output to the declared schemas (AC-B#refresh).
    def refresh_output
      result = @instance.result
      return if gem_failure?(result)

      klass = @instance.class
      if result.success?
        refresh_success(result, klass.output_schema)
      elsif (schema = coded_schema(result))
        refresh_coded(result, schema)
      elsif klass.typed_outcomes?
        refresh_empty(result)
      elsif klass.output_schema
        refresh_best_effort(result, klass.output_schema)
      end
    end

    def refresh_success(result, schema)
      return if schema.nil?

      fields = captured_fields(schema, result)
      success_output(result, schema, fields)
    end

    def refresh_best_effort(result, schema)
      best_effort_output(result, schema, captured_fields(schema, result))
    end

    # The output schema the failure's or skip's own code declared, if any.
    def coded_schema(result)
      klass = @instance.class
      result.skipped? ? klass.skip_output_schema(result.code) : klass.failure_output_schema(result.code)
    end

    # A code with its own schema is built only from the keywords it was recorded with, then validated like a success.
    def refresh_coded(result, schema)
      names = schema.attribute_names
      fields = @instance.__send__(:recorded_keywords_for, result).transform_keys(&:to_sym).slice(*names)
      success_output(result, schema, fields)
    end

    # Typed outcomes: a code without a schema carries nothing.
    def refresh_empty(result)
      result.output = {}
      result.output_fields_set = []
    end

    def gem_failure?(result)
      result.failure? && Action::GEM_FAILURE_CODES.include?(result.code)
    end

    # Declared fields whose ivar is defined, overlaid with the keywords the verb recorded (keywords win).
    def captured_fields(schema, result)
      names = schema.attribute_names
      fields = {}
      ivar_pairs(schema, names).each do |name, ivar|
        fields[name] = @instance.instance_variable_get(ivar) if @instance.instance_variable_defined?(ivar)
      end
      keywords = @instance.__send__(:recorded_keywords_for, result)
      keywords.each { |name, value| fields[name.to_sym] = value if names.include?(name.to_sym) } unless keywords.empty?
      fields
    end

    # The +[name, :@name]+ pairs of a schema, built once per schema and rebuilt if its field names ever change.
    def ivar_pairs(schema, names)
      cached = schema.instance_variable_get(IVAR_PAIRS)
      return cached.last if cached && cached.first == names

      pairs = names.map { |name| [name, :"@#{name}"].freeze }.freeze
      schema.instance_variable_set(IVAR_PAIRS, [names, pairs].freeze)
      pairs
    end

    def success_output(result, schema, fields)
      struct = schema.new(fields)
      if struct.valid?
        assign_output(result, struct)
        result.output_fields_set = fields.keys
      else
        adopt(invalid_output(struct, fields))
      end
    end

    def best_effort_output(result, schema, fields)
      assign_output(result, schema.new(fields))
      result.output_fields_set = fields.keys
    end

    def invalid_output(struct, fields)
      metadata = @instance.class.failure_declarations.dig(:invalid_output, :metadata) || {}
      failure = Failure.new(code: :invalid_output, message: 'output failed validation', metadata: metadata)
      failure.absorb_errors_from(struct)
      assign_output(failure, struct)
      failure.output_fields_set = fields.keys
      failure
    end

    # Assigns an output struct, then removes the incidental +output: ["is invalid"]+ FieldStruct adds for an invalid
    # one; an +output+ error the caller recorded earlier survives.
    def assign_output(result, struct)
      before = result.errors[:output]
      before = before.dup unless before.empty?
      result.output = struct
      result.errors.clear(:output)
      before.each { |message| result.errors.add(:output, message) }
    end
  end
end
