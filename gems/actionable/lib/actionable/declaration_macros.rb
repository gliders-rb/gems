# frozen_string_literal: true

module Actionable
  # Class-level +fails+ / +skips+ declarations and their readers.
  module DeclarationMacros
    # Declares a failure code with an optional default message, neutral metadata and an optional output schema.
    #
    # @param code [Symbol, String]
    # @param message [String, nil] used when a failure with this code is recorded without a message
    # @param desc [String, nil] prose for people (+describe+, the docs adapter); never part of the metadata
    # @param metadata [Object] opaque; attached to results and shown in +describe+
    # @yield an optional output DSL
    # @return [Hash{Symbol=>Hash{Symbol=>Object}}] {#declared_failures}
    # @raise [ArgumentError] for a block on a gem failure code, or a +desc:+ that is not a String
    def fails(code, message = nil, desc: nil, **metadata, &block)
      code = declared_code!(code, 'fails', ':out_of_stock')
      described!(desc, 'fails', code)
      if block && Action::GEM_FAILURE_CODES.include?(code)
        raise ArgumentError, "#{Actionable.label_for(self)}: #{code.inspect} is a gem failure code and cannot declare " \
                             'an output schema; remove the block (the gem builds this failure itself)'
      end

      declare(failure_declarations, code, entry(message, metadata, desc), block)
      declared_failures
    end

    # Declares a skip code, like {#fails}.
    #
    # @param code [Symbol, String]
    # @param message [String, nil]
    # @param desc [String, nil] prose for people; never part of the metadata
    # @param metadata [Object]
    # @yield an optional output DSL
    # @return [Hash{Symbol=>Hash{Symbol=>Object}}] {#declared_skips}
    # @raise [ArgumentError] for a +desc:+ that is not a String
    def skips(code, message = nil, desc: nil, **metadata, &block)
      code = declared_code!(code, 'skips', ':nothing_to_do')
      described!(desc, 'skips', code)
      declare(skip_declarations, code, entry(message, metadata, desc), block)
      declared_skips
    end

    # @return [Hash{Symbol=>Hash{Symbol=>Object}}] +{code => metadata}+ of declared failures
    def declared_failures = failure_declarations.transform_values { |declaration| declaration[:metadata] }

    # @return [Hash{Symbol=>Hash{Symbol=>Object}}] +{code => metadata}+ of declared skips
    def declared_skips = skip_declarations.transform_values { |declaration| declaration[:metadata] }

    # @return [Hash{Symbol=>Hash{Symbol=>Object}}] +{code => {message:, metadata:}}+, plus +:description+ when +desc:+ was
    #   given and +:output_schema+ for a declaration with a block
    def failure_declarations = (@failure_declarations ||= {})

    # @return [Hash{Symbol=>Hash{Symbol=>Object}}] the same for skips
    def skip_declarations = (@skip_declarations ||= {})

    # @param code [Symbol, String]
    # @return [Class, nil] the output schema declared for the failure code
    def failure_output_schema(code) = failure_declarations.dig(code.to_sym, :output_schema)

    # @param code [Symbol, String]
    # @return [Class, nil] the output schema declared for the skip code
    def skip_output_schema(code) = skip_declarations.dig(code.to_sym, :output_schema)

    # @param code [Symbol, String]
    # @return [Boolean] true when no failures are declared, +code+ is declared, or it is a gem code
    def allows_failure_code?(code)
      code = code.to_sym
      failure_declarations.empty? || failure_declarations.key?(code) || Action::GEM_FAILURE_CODES.include?(code)
    end

    # @param code [Symbol, String]
    # @return [Boolean] true when no skips are declared or +code+ is declared
    def allows_skip_code?(code)
      skip_declarations.empty? || skip_declarations.key?(code.to_sym)
    end

    private

    # The code as a Symbol, or an ArgumentError naming the action when no verb could ever record it (AC-B#declare).
    def declared_code!(code, macro, example)
      return code.to_sym if (code.is_a?(Symbol) || code.is_a?(String)) && Action::CODE_FORMAT.match?(code.to_s)

      raise ArgumentError, "#{Actionable.label_for(self)}: #{macro} code #{code.inspect} is not an identifier; " \
                           "use a Symbol like #{example}"
    end

    def described!(desc, macro, code)
      return if desc.nil? || desc.is_a?(String)

      raise ArgumentError, "#{Actionable.label_for(self)}: #{macro} code #{code.inspect} desc: takes a String, got #{desc.class}"
    end

    def entry(message, metadata, desc)
      declaration = { message: message, metadata: metadata.freeze }
      declaration[:description] = desc.frozen? ? desc : desc.dup.freeze if desc
      declaration
    end

    def declare(declarations, code, declaration, block)
      declaration[:output_schema] = SchemaBuilder.output(self, &block) if block
      declarations[code] = declaration
    end
  end
end
