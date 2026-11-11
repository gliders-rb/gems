# frozen_string_literal: true

require 'bigdecimal'
require 'google/protobuf'
require 'google/protobuf/descriptor_pb'
require 'google/protobuf/timestamp_pb'
require 'google/protobuf/struct_pb'
require 'google/protobuf/well_known_types'
require 'field_struct'

unless defined?(FieldStruct::Introspection)
  raise LoadError, 'field_struct-protobuf needs FieldStruct::Introspection (field_struct >= 1.0.0.pre1); ' \
                   'upgrade field_struct or check that its version is loaded'
end

require_relative 'protobuf/version'
require_relative 'protobuf/names'
require_relative 'protobuf/check'
require_relative 'protobuf/numbers'
require_relative 'protobuf/scalar_types'
require_relative 'protobuf/descriptor_builder'
require_relative 'protobuf/printer'
require_relative 'protobuf/references'
require_relative 'protobuf/properties'
require_relative 'protobuf/registry'
require_relative 'protobuf/zone'
require_relative 'protobuf/json_value'
require_relative 'protobuf/encoder'
require_relative 'protobuf/decoder'

# The field_struct namespace.
module FieldStruct
  # Protocol Buffers support for field_struct classes: `.proto` text, runtime messages, and the binary wire format.
  module Protobuf
    class << self
      # Describes the protobuf file for a struct class.
      #
      # @param klass [::Class<FieldStruct::Base>] a named +FieldStruct::Base+ subclass
      # @param serialization [::Symbol] the +serialize+ format whose names become field names
      # @return [::Object] a +Google::Protobuf::FileDescriptorProto+
      # @raise [::ArgumentError] for a bad argument or an unmappable field
      def file_descriptor(klass, serialization: :protobuf)
        checked = Check.call(klass)
        DescriptorBuilder.new(checked, serialization).call
      end

      # Prints the `.proto` text for a struct class.
      #
      # @param klass [::Class<FieldStruct::Base>]
      # @param serialization [::Symbol]
      # @return [::String]
      def proto(klass, serialization: :protobuf)
        descriptor = file_descriptor(klass, serialization: serialization)
        Printer.new(descriptor, klass).call
      end

      # Looks up (building and registering it the first time) the message class for a struct class.
      #
      # @param klass [::Class<FieldStruct::Base>] a named +FieldStruct::Base+ subclass
      # @param serialization [::Symbol] the +serialize+ format whose names become field names
      # @return [::Class] a +Google::Protobuf+ message class
      # @raise [::ArgumentError] for a bad argument, an unmappable field, a cycle or a second serialization
      def message_class(klass, serialization: :protobuf)
        Registry.message_class(Check.call(klass), serialization)
      end

      # Converts a struct to an instance of its message class.
      #
      # @param struct [FieldStruct::Base] an instance of a struct class
      # @param serialization [::Symbol]
      # @return [::Object] a message instance
      # @raise [::ArgumentError] for a bad argument or a value that cannot be written
      def to_message(struct, serialization: :protobuf)
        Check.call(struct.class)
        Encoder.new(serialization).call(struct)
      end

      # Converts a message instance back to a struct.
      #
      # @param klass [::Class<FieldStruct::Base>] a named +FieldStruct::Base+ subclass
      # @param message [::Object] a message instance of the class's message
      # @param serialization [::Symbol]
      # @return [FieldStruct::Base]
      def from_message(klass, message, serialization: :protobuf)
        expected = message_class(klass, serialization: serialization)
        Check.message!(klass, message, expected)
        Decoder.new(serialization).call(klass, message)
      end

      # Serializes a struct to protobuf wire bytes.
      #
      # @param struct [FieldStruct::Base] an instance of a struct class
      # @param serialization [::Symbol]
      # @return [::String] ASCII-8BIT bytes
      def encode(struct, serialization: :protobuf)
        built = to_message(struct, serialization: serialization)
        built.class.encode(built)
      end

      # Parses protobuf wire bytes into a struct.
      #
      # @param klass [::Class<FieldStruct::Base>] a named +FieldStruct::Base+ subclass
      # @param bytes [::String] protobuf binary
      # @param serialization [::Symbol]
      # @return [FieldStruct::Base]
      # @raise [::Google::Protobuf::ParseError] for malformed bytes
      def decode(klass, bytes, serialization: :protobuf)
        raw = Check.bytes!(bytes)
        parsed = message_class(klass, serialization: serialization).decode(raw)
        from_message(klass, parsed, serialization: serialization)
      end

      # @param klass [::Class] a named class
      # @return [::String] the package; empty for a top-level class
      def package(klass) = Names.package(klass)

      # @param klass [::Class] a named class
      # @return [::String] the message name
      def message_name(klass) = Names.message_name(klass)

      # @param klass [::Class] a named class
      # @return [::String] the full name with a leading dot
      def full_name(klass) = Names.full_name(klass)

      # @param klass [::Class] a named class
      # @return [::String] the file name
      def file_name(klass) = Names.file_name(klass)
    end
  end
end
