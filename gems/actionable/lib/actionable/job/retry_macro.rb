# frozen_string_literal: true

module Actionable
  module Job
    # Class macro on Action: whether +retry+ metadata decides a job's disposition (on by default).
    module RetryMacro
      # @param enabled [Boolean]
      # @return [Boolean]
      def honor_retry_metadata(enabled: true)
        @honor_retry_metadata = enabled ? true : false
      end

      # @return [Boolean] set here, else the nearest ancestor's, else +true+
      def honor_retry_metadata?
        return @honor_retry_metadata if instance_variable_defined?(:@honor_retry_metadata)

        superclass.respond_to?(:honor_retry_metadata?) ? superclass.honor_retry_metadata? : true
      end
    end
  end
end
