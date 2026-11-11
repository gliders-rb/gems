# frozen_string_literal: true

module Actionable
  module RSpec
    # Example-group helpers that stand in for an action's +run+. +allow_*+ permits the call, +stub_*+ also expects it;
    # both build a real result and return it. The +actionable_*_result+ builders make a plain result without stubbing.
    module Stubs
      # @param action [Class] the action whose +run+ is stood in for
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @return [Actionable::Success]
      def allow_actionable_success(action, message: nil, output: {}, errors: {})
        stand_in_for_run(action, :allow, :success, message: message, output: output, errors: errors)
      end

      # Like {#allow_actionable_success}, and expects +action.run+ to be called.
      #
      # @param action [Class] the action whose +run+ is stood in for
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @return [Actionable::Success]
      def stub_actionable_success(action, message: nil, output: {}, errors: {})
        stand_in_for_run(action, :expect, :success, message: message, output: output, errors: errors)
      end

      # @param action [Class] the action whose +run+ is stood in for
      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Failure]
      def allow_actionable_failure(action, code: :error, message: nil, output: {}, errors: {}, metadata: {}) # rubocop:disable Metrics/ParameterLists
        stand_in_for_run(action, :allow, :failure, code: code, message: message, output: output, errors: errors,
                                                   metadata: metadata)
      end

      # Like {#allow_actionable_failure}, and expects +action.run+ to be called.
      #
      # @param action [Class] the action whose +run+ is stood in for
      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Failure]
      def stub_actionable_failure(action, code: :error, message: nil, output: {}, errors: {}, metadata: {}) # rubocop:disable Metrics/ParameterLists
        stand_in_for_run(action, :expect, :failure, code: code, message: message, output: output, errors: errors,
                                                    metadata: metadata)
      end

      # @param action [Class] the action whose +run+ is stood in for
      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Skipped]
      def allow_actionable_skip(action, code: :skipped, message: nil, output: {}, metadata: {})
        stand_in_for_run(action, :allow, :skip, code: code, message: message, output: output, metadata: metadata)
      end

      # Like {#allow_actionable_skip}, and expects +action.run+ to be called.
      #
      # @param action [Class] the action whose +run+ is stood in for
      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Skipped]
      def stub_actionable_skip(action, code: :skipped, message: nil, output: {}, metadata: {})
        stand_in_for_run(action, :expect, :skip, code: code, message: message, output: output, metadata: metadata)
      end

      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @return [Actionable::Success] a plain success, not stubbed
      def actionable_success_result(message: nil, output: {}, errors: {})
        Results.new.success(message: message, output: output, errors: errors)
      end

      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param errors [Hash{Symbol=>String, Array<String>}] error messages by field
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Failure] a plain failure, not stubbed
      def actionable_failure_result(code: :error, message: nil, output: {}, errors: {}, metadata: {})
        Results.new.failure(code: code, message: message, output: output, errors: errors, metadata: metadata)
      end

      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash{Symbol=>Object}, ::FieldStruct::Base] the output the result carries
      # @param metadata [Hash{Symbol=>Object}] merged over the declared metadata
      # @return [Actionable::Skipped] a plain skip, not stubbed
      def actionable_skip_result(code: :skipped, message: nil, output: {}, metadata: {})
        Results.new.skip(code: code, message: message, output: output, metadata: metadata)
      end

      private

      # Builds a result of +kind+ for +action+ and makes +action.run+ answer it for any arguments, noting each answer
      # for outcome coverage.
      def stand_in_for_run(action, mode, kind, **fields)
        built = Results.new(action).public_send(kind, **fields)
        double = mode == :expect ? expect(action) : allow(action)
        double.to receive(:run) do |*_args, **_kwargs|
          Actionable::RSpec.note_stub(action, built)
          built
        end
        built
      end
    end
  end
end
