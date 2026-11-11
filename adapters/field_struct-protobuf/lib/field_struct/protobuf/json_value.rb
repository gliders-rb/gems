# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Checks and normalizes the content of a +:value+ field for +Google::Protobuf::Value.from_ruby+ (PB-B42).
    module JsonValue
      module_function

      # @param value [::Object] what the field holds
      # @param key [::String] the property key, for the error
      # @return [::Object] the same JSON value with Symbol hash keys turned into Strings
      # @raise [::ArgumentError] for anything that is not a JSON value
      def call(value, key)
        case value
        when nil, true, false, ::String, ::Integer, ::Float then value
        when ::Array then value.map { |item| call(item, key) }
        when ::Hash then value.to_h { |name, item| [text(name, key), call(item, key)] }
        else refuse(value, key)
        end
      end

      # @param name [::Object] a hash key
      # @param key [::String]
      # @return [::String]
      def text(name, key)
        return name.to_s if name.is_a?(::String) || name.is_a?(::Symbol)

        refuse(name, key)
      end

      # @param value [::Object]
      # @param key [::String]
      # @raise [::ArgumentError] always
      def refuse(value, key)
        raise ::ArgumentError, "#{key}: a :value field holds JSON values (Hash, Array, String, Numeric, true, false, nil); " \
                               "got #{value.class}"
      end
    end
  end
end
