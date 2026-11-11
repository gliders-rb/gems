# frozen_string_literal: true

module Actionable
  module Tools
    # Builds the JSON Schema of the result envelope a tool call returns (AT-B15..B18).
    module OutputSchema
      STATUSES = %w[success failure skipped].freeze
      ERRORS = { 'type' => 'object', 'additionalProperties' => { 'type' => 'array', 'items' => { 'type' => 'string' } } }.freeze

      module_function

      # @param action [Class] an +Actionable::Action+ subclass
      # @return [::Hash{::String=>::Object}] a fresh schema (draft 2020-12)
      def build(action)
        schema = {
          '$schema' => FieldStruct::JSONSchema::DRAFT,
          'type' => 'object',
          'required' => RESULT_KEYS.dup,
          'properties' => properties(action)
        }
        add_output(schema, action.output_schema) if action.output_schema
        schema
      end

      # @param action [Class]
      # @return [::Hash{::String=>::Object}]
      def properties(action)
        {
          'status' => { 'enum' => STATUSES.dup },
          'code' => { 'type' => 'string', 'description' => code_description(action) },
          'message' => { 'type' => %w[string null] },
          'output' => {},
          'errors' => Marshal.load(Marshal.dump(ERRORS)),
          'metadata' => { 'type' => 'object' }
        }
      end

      # @param action [Class]
      # @return [::String] the text for the +code+ property
      def code_description(action)
        text = +'"success", or why the run failed or was skipped.'
        failures = action.declared_failures.keys
        skips = action.declared_skips.keys
        text << " Declared failures: #{failures.join(', ')}." unless failures.empty?
        text << " Declared skips: #{skips.join(', ')}." unless skips.empty?
        text << ' "invalid_input" means the arguments were rejected; see errors.'
      end

      # @param schema [::Hash{::String=>::Object}] modified in place
      # @param output [Class] the action's output struct class
      # @return [void]
      def add_output(schema, output)
        body = FieldStruct::JSONSchema.generate(output).except('$schema')
        shared = body.delete('$defs')
        schema['$defs'] = shared if shared
        schema['if'] = { 'properties' => { 'status' => { 'const' => 'success' } } }
        schema['then'] = { 'properties' => { 'output' => body } }
      end
    end
  end
end
