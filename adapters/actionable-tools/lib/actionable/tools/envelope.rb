# frozen_string_literal: true

module Actionable
  module Tools
    # Turns an +Actionable::Result+ into the six-key Hash a tool call returns (AT-B21).
    module Envelope
      module_function

      # @param result [Actionable::Result]
      # @return [::Hash{::String=>::Object}] status, code, message, output, errors and metadata as plain JSON values
      def build(result)
        {
          'status' => result.status.to_s,
          'code' => result.code.to_s,
          'message' => result.message,
          'output' => plain(result.output),
          'errors' => plain(result.errors.to_h),
          'metadata' => result.respond_to?(:metadata) ? plain(result.metadata) : {}
        }
      end

      # A JSON round trip through Oj, so structs and BigDecimals become their JSON form and symbols become strings.
      #
      # @param value [Object]
      # @return [Object] JSON-safe plain data
      def plain(value)
        value = value.as_json if value.respond_to?(:as_json)
        Oj.load(Oj.dump(value, mode: :compat), mode: :compat)
      end
    end
  end
end
