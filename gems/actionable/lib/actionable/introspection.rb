# frozen_string_literal: true

module Actionable
  # Class-level +describe+ and +describe_text+.
  module Introspection
    # A Hash summary of the action: schemas, steps, declarations, hooks, measure mode.
    #
    # @return [Hash{Symbol=>Object}]
    def describe
      summary = { name: name, description: desc, input: describe_input }
      summary[:output] = output_schema&.metadata&.to_h
      summary[:steps] = steps.map { |entry| step_entry(entry) }
      summary[:failures] = describe_declarations(failure_declarations)
      summary[:skips] = describe_declarations(skip_declarations)
      summary[:hooks] = describe_hooks
      summary[:measure] = measure
      summary[:transactional] = describe_transactional
      summary[:calls] = HiddenCalls.of(self)
      summary
    end

    # Describes the action in prose for people (the docs adapter, {#describe}); a run never reads it. Given once per
    # class and not inherited. With no argument it reads.
    #
    # @param text [String, nil]
    # @return [String, nil] the description, or nil when none was given
    # @raise [ArgumentError] when +text+ is not a String
    # @raise [Actionable::DefinitionError] when the class already has a description
    def desc(text = nil)
      return (instance_variable_defined?(:@description) ? @description : nil) if text.nil?
      raise ArgumentError, "#{Actionable.label_for(self)}: desc takes a String, got #{text.class}" unless text.is_a?(String)

      if instance_variable_defined?(:@description)
        raise DefinitionError, "#{Actionable.label_for(self)} already has a description; give it once, with desc or description"
      end

      @description = text.frozen? ? text : text.dup.freeze
    end

    # The same macro as {#desc}.
    #
    # @param text [String, nil]
    # @return [String, nil]
    def description(text = nil) = desc(text)

    # A multi-line, human-readable summary (no trailing newline).
    #
    # @return [String]
    def describe_text
      info = describe
      lines = [header_line(info), "  Input:#{schema_text(info[:input], input_schema, input_dispatch)}"]
      lines << "  Output:#{schema_text(info[:output], output_schema, nil)}"
      lines.concat(step_lines(info[:steps]))
      lines.concat(declaration_lines('Failures', info[:failures]), declaration_lines('Skips', info[:skips]))
      lines.concat(hook_lines(info[:hooks]))
      lines << "  Calls: #{info[:calls].map { |child| step_label(child) }.join(', ')} (found in source)" if info[:calls].any?
      lines.join("\n")
    end

    private

    def describe_input
      return { discriminated_on: input_dispatch.discriminator, shapes: input_dispatch.variants } if input_dispatch

      input_schema&.metadata&.to_h
    end

    # One step's entry: its kind, name, options (without +desc:+) and description; +guard:+ when guarded; a case
    # step's +branches:+ and +default:+ (AC-B#describe).
    def step_entry(step)
      entry = { type: step.kind, name: step.name, options: step.options.except(:desc), description: step.options[:desc] }
      guard = guard_labels(step.options)
      entry[:guard] = guard if guard
      return entry unless step.is_a?(Steps::Case)

      entry[:branches] = step.branches.map { |value, target| { on: value, step: step_entry(target) } }
      default_step = step.default_step
      entry[:default] = default_step ? step_entry(default_step) : nil
      entry
    end

    def guard_labels(options)
      labels = %i[if unless].filter_map { |key| [key, guard_label(options[key])] if options.key?(key) }
      labels.empty? ? nil : labels.to_h
    end

    # A method name as is; a callable's own +desc+ when it has one; else a neutral phrase.
    def guard_label(guard)
      return guard.to_s if guard.is_a?(Symbol) || guard.is_a?(String)

      label = guard.desc if guard.respond_to?(:desc)
      label.is_a?(String) ? label : 'a custom condition'
    end

    def describe_declarations(declarations)
      declarations.transform_values do |declaration|
        entry = declaration.slice(:message, :metadata)
        entry[:description] = declaration[:description]
        schema = declaration[:output_schema]
        schema ? entry.merge(output: schema.metadata.to_h) : entry
      end
    end

    def describe_hooks
      hooks = { on_success: success_hooks, on_failure: failure_hooks, on_skip: skip_hooks, always: always_hooks }
      hooks[:after_commit] = after_commit_hooks if respond_to?(:after_commit_hooks)
      hooks.transform_values { |list| list.map { |hook| step_entry(hook) } }
    end

    def describe_transactional
      respond_to?(:transaction_config) ? transaction_config : nil
    end

    def header_line(info)
      transactional = info[:transactional] ? ', transactional' : ''
      "#{Actionable.label_for(self)} (measure: #{info[:measure]}#{transactional})"
    end

    def schema_text(summary, schema, dispatch)
      return " (discriminated on #{dispatch.discriminator}: #{dispatch.variants.map(&:inspect).join(', ')})" if dispatch
      return ' (free-form)' if summary.nil?

      "\n#{schema.metadata.describe.lines(chomp: true).map { |line| "  #{line}" }.join("\n")}"
    end

    def step_lines(steps)
      return ['  Steps:', '    (none)'] if steps.empty?

      ['  Steps:', *steps.map { |step| "    - #{step_label(step[:name])} (#{step[:type]})" }]
    end

    def step_label(name)
      name.is_a?(Class) ? Actionable.label_for(name) : name.to_s
    end

    def declaration_lines(title, declarations)
      return [] if declarations.empty?

      ["  #{title}:", *declarations.map { |code, declaration| declaration_line(code, declaration) }]
    end

    def declaration_line(code, declaration)
      metadata = declaration[:metadata]
      line = "    - #{code}"
      line += " (#{metadata.map { |key, value| "#{key}: #{value.inspect}" }.join(', ')})" unless metadata.empty?
      declaration[:message] ? "#{line}: #{declaration[:message]}" : line
    end

    def hook_lines(hooks)
      present = hooks.reject { |_section, entries| entries.empty? }
      return [] if present.empty?

      ['  Hooks:', *present.map { |section, entries| "    #{section}: #{entries.map { |e| step_label(e[:name]) }.join(', ')}" }]
    end
  end
end
