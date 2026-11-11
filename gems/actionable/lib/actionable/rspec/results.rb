# frozen_string_literal: true

module Actionable
  module RSpec
    # Builds the result objects the stub helpers return. With an action it mirrors what a real run would produce:
    # declared messages and metadata, the action's output shaping, its own result classes under typed outcomes.
    class Results
      # @param action [Class, nil] the action to mirror, or nil for plain results
      def initialize(action = nil)
        @action = action
      end

      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @return [Actionable::Success]
      def success(message: nil, output: {}, errors: {})
        shaped, fields = shape(:success, :success, output)
        finish(Success.new(message: message, output: shaped), fields, errors)
      end

      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Failure]
      def failure(code: :error, message: nil, output: {}, errors: {}, metadata: {})
        code = code.to_sym
        declaration = declaration_for(:failure, code)
        shaped, fields = shape(:failure, code, output)
        result = Failure.new(code: code, message: message || declaration[:message], output: shaped,
                             metadata: merged_metadata(declaration, metadata))
        finish(result, fields, errors)
      end

      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Skipped]
      def skip(code: :skipped, message: nil, output: {}, metadata: {})
        code = code.to_sym
        declaration = declaration_for(:skip, code)
        shaped, fields = shape(:skip, code, output)
        result = Skipped.new(code: code, message: message || declaration[:message], output: shaped,
                             metadata: merged_metadata(declaration, metadata))
        finish(result, fields, {})
      end

      private

      def finish(result, fields, errors)
        errors.each do |field, messages|
          Array(messages).each { |message| result.errors.add(field, message.to_s) }
        end
        result.output_fields_set = fields
        @action ? @action.own_result(result) : result
      end

      # The declaration of a code, after the declared-code check (AC-B#stubdeclared); empty without an action.
      def declaration_for(kind, code)
        return {} unless @action

        RSpec.check_declared!(@action, kind, code)
        declarations = kind == :failure ? @action.failure_declarations : @action.skip_declarations
        declarations.fetch(code, {})
      end

      # Explicit metadata overrides the declared keys; with none given the declared (frozen) hash is attached as is.
      def merged_metadata(declaration, explicit)
        declared = declaration.fetch(:metadata, {})
        explicit.empty? ? declared : declared.merge(explicit)
      end

      # @return [Array(Object, Array<Symbol>)] the output a real run would carry, and the fields it counts as set
      def shape(kind, code, output)
        fields = output_fields(output)
        return [output, fields.keys] unless @action

        schema = shaping_schema(kind, code)
        return build_struct(schema, code, fields) if schema
        return [output, fields.keys] unless typed? && kind != :success && !gem_code?(kind, code)

        unless fields.empty?
          raise ArgumentError, "#{label} output for #{code.inspect}, which declares no output schema; a real run refuses it"
        end

        [{}, []]
      end

      def output_fields(output)
        case output
        when FieldStruct::Base then output.class.attribute_names.to_h { |name| [name, output.public_send(name)] }
        when Hash then output.transform_keys(&:to_sym)
        else {}
        end
      end

      # Success is shaped only under typed outcomes; a failure or skip code with a schema is always shaped.
      def shaping_schema(kind, code)
        return nil unless @action

        case kind
        when :success then typed? ? @action.output_schema : nil
        when :failure then @action.failure_output_schema(code)
        else @action.skip_output_schema(code)
        end
      end

      def build_struct(schema, code, fields)
        names = schema.attribute_names
        fields = fields.slice(*names)
        struct = schema.new(fields)
        unless struct.valid?
          raise ArgumentError, "#{label} output for #{code.inspect} breaks its schema (#{struct.errors.full_messages.join(', ')}); " \
                               'a real run would end as invalid_output'
        end
        [struct, fields.keys]
      end

      def typed?
        @action&.typed_outcomes? || false
      end

      def gem_code?(kind, code)
        kind == :failure && Action::GEM_FAILURE_CODES.include?(code)
      end

      def label
        Actionable.label_for(@action)
      end
    end
  end
end
