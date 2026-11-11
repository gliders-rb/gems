# frozen_string_literal: true

module Actionable
  # Instance side of the declared outcomes: strictness checks and the results the verbs build from declarations.
  module Declarations
    private

    # @return [Actionable::Failure] a failure carrying the code's declared message (when none given) and metadata
    def build_failure(code, message)
      code = check_code!(code, :failure, ':out_of_stock')
      declaration = declared_failure(code)
      Failure.new(code: code, message: message || declaration[:message], metadata: declaration.fetch(:metadata, {}))
    end

    # @return [Actionable::Skipped]
    def build_skip(code, message, output)
      code = check_code!(code, :skip, ':already_done')
      declaration = declared_skip(code)
      Skipped.new(code: code, message: message || declaration[:message], output: output,
                  metadata: declaration.fetch(:metadata, {}))
    end

    # @return [Hash{Symbol=>Object}] the declaration of a failure code (empty when undeclared)
    # @raise [Actionable::DefinitionError] when the action declares failures and +code+ is not one of them
    def declared_failure(code)
      klass = self.class
      refuse_undeclared!(:fails, code, klass.failure_declarations) unless klass.allows_failure_code?(code)
      klass.failure_declarations.fetch(code.to_sym, {})
    end

    # @return [Hash{Symbol=>Object}]
    # @raise [Actionable::DefinitionError] when the action declares skips and +code+ is not one of them
    def declared_skip(code)
      klass = self.class
      refuse_undeclared!(:skips, code, klass.skip_declarations) unless klass.allows_skip_code?(code)
      klass.skip_declarations.fetch(code.to_sym, {})
    end

    # Whether +output:+ names the output of a failure with this code (a declared schema, or typed outcomes).
    def output_keyword?(kind, code)
      !output_schema_for(kind, code).nil? || self.class.typed_outcomes?
    end

    # Stores the output given to a failure: remembered as keywords (a schema or typed outcomes builds the struct
    # at refresh), or kept as given for a gem failure code.
    def record_output(kind, result, output)
      fields = output_fields(output)
      return result.output = output if kind == :failure && Action::GEM_FAILURE_CODES.include?(result.code)

      refuse_output!(kind, result.code) if typed_without_schema?(kind, result.code) && !fields.empty?
      remember(result, fields)
    end

    def output_fields(output)
      case output
      when Hash then output
      when FieldStruct::Base then output.class.attribute_names.to_h { |name| [name, output.public_send(name)] }
      else raise ArgumentError, "#{Actionable.label_for(self.class)}: output: must be a Hash or a FieldStruct, got #{output.class}"
      end
    end

    def typed_without_schema?(kind, code)
      self.class.typed_outcomes? && output_schema_for(kind, code).nil?
    end

    def output_schema_for(kind, code)
      kind == :failure ? self.class.failure_output_schema(code) : self.class.skip_output_schema(code)
    end

    def refuse_output!(kind, code)
      macro = kind == :failure ? 'fails' : 'skips'
      raise DefinitionError, "#{Actionable.label_for(self.class)} #{macro} with #{code.inspect} and output, but " \
                             "#{code.inspect} declares no output schema; declare one with `#{macro} #{code.inspect} do … end`"
    end

    def refuse_undeclared!(macro, code, declarations)
      raise DefinitionError, "#{Actionable.label_for(self.class)} #{macro} with #{code.inspect}, which it does not " \
                             "declare; declare it with `#{macro} #{code.inspect}` " \
                             "(declared: #{declarations.keys.map(&:inspect).join(', ')})"
    end
  end
end
