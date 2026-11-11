# frozen_string_literal: true

module Actionable
  # Class-level +describe+ and +describe_text+.
  module Introspection
    # A Hash summary of the action: schemas, steps, declarations, hooks, measure mode.
    #
    # @return [Hash{Symbol=>Object}]
    def describe
      summary = { name: name, input: describe_input }
      summary[:output] = output_schema&.metadata&.to_h
      summary[:steps] = steps.map { |entry| { type: entry.kind, name: entry.name, options: entry.options } }
      summary[:failures] = describe_declarations(failure_declarations)
      summary[:skips] = describe_declarations(skip_declarations)
      summary[:hooks] = describe_hooks
      summary[:measure] = measure
      summary[:transactional] = describe_transactional
      summary
    end

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
      lines.join("\n")
    end

    private

    def describe_input
      return { discriminated_on: input_dispatch.discriminator, shapes: input_dispatch.variants } if input_dispatch

      input_schema&.metadata&.to_h
    end

    def describe_declarations(declarations)
      declarations.transform_values do |declaration|
        entry = declaration.slice(:message, :metadata)
        schema = declaration[:output_schema]
        schema ? entry.merge(output: schema.metadata.to_h) : entry
      end
    end

    def describe_hooks
      hooks = { on_success: success_hooks, on_failure: failure_hooks, on_skip: skip_hooks, always: always_hooks }
      hooks[:after_commit] = after_commit_hooks if respond_to?(:after_commit_hooks)
      hooks.transform_values { |list| list.map(&:name) }
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
      present = hooks.reject { |_section, names| names.empty? }
      return [] if present.empty?

      ['  Hooks:', *present.map { |section, names| "    #{section}: #{names.map { |n| step_label(n) }.join(', ')}" }]
    end
  end
end
