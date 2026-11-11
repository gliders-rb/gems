# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # Reads the value of a +json_schema:+ option or a +json_schema+ hook (JS-B13).
    module Override
      module_function

      # @param value [::Object]
      # @return [::Hash{::String=>::Object}, nil] the schema, or nil when +value+ is neither a Hash nor a boolean
      def normalize(value)
        case value
        when ::Hash then value
        when true then {}
        when false then { 'not' => {} }
        end
      end
    end
  end
end
