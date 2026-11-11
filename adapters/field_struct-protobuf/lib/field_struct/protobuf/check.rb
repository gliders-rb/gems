# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Argument checking shared by the public functions (section 4).
    module Check
      module_function

      # @param klass [::Object] the class to check
      # @return [::Class] the class
      # @raise [::ArgumentError] when it is not a named FieldStruct::Base subclass
      def call(klass)
        unless klass.is_a?(::Class) && klass < FieldStruct::Base
          raise ::ArgumentError, "FieldStruct::Protobuf expects a FieldStruct::Base subclass, got #{klass.inspect}"
        end
        return klass if FieldStruct::Introspection.named?(klass)

        raise ::ArgumentError,
              'FieldStruct::Protobuf needs a named class (assign it to a constant): its message and package are named after it'
      end

      # @param bytes [::Object]
      # @return [::String] the bytes
      # @raise [::ArgumentError] when they are not a String
      def bytes!(bytes)
        return bytes if bytes.is_a?(::String)

        raise ::ArgumentError, "FieldStruct::Protobuf.decode expects the bytes as a String, got #{bytes.class}"
      end

      # @param klass [::Class] the struct class
      # @param message [::Object] what was given as a message
      # @param expected [::Class] the registered message class of +klass+
      # @return [::Object] the message
      # @raise [::ArgumentError] when it is not an instance of +expected+
      def message!(klass, message, expected)
        return message if message.instance_of?(expected)

        got = message.class.respond_to?(:descriptor) ? message.class.descriptor.name : message.class
        raise ::ArgumentError, "FieldStruct::Protobuf.from_message(#{klass}) expects a #{klass} message, got #{got}"
      end
    end
  end
end
