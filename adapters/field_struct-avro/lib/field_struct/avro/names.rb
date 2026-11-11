# frozen_string_literal: true

module FieldStruct
  module Avro
    # The Avro full names claimed so far in one schema (AV-B13): what holds each name, so a second claim of the
    # same name is either the same thing (a reference) or a clash.
    class Names
      # Avro's name rule.
      # @return [::Regexp]
      VALID = /\A[A-Za-z_][A-Za-z0-9_]*\z/

      Claim = Struct.new(:token, :label)
      private_constant :Claim

      def initialize
        @claims = {}
        @struct_names = {}
      end

      # Claims a full name for +token+.
      #
      # @param full [::String]
      # @param token [::Object] what holds the name (a class, or the content of an enum)
      # @param label [::String] how an error names the holder
      # @param fix [::String] the advice when the name is taken by something else
      # @return [:new, :seen] +:seen+ when the same token already holds it
      # @raise [::ArgumentError] when something else holds it
      def claim(full, token, label, fix)
        existing = @claims[full]
        if existing
          return :seen if existing.token == token

          raise ::ArgumentError, "FieldStruct::Avro: #{label} and #{existing.label} both become Avro #{full}; #{fix}"
        end
        @claims[full] = Claim.new(token, label)
        :new
      end

      # @param klass [::Class]
      # @return [::String, nil] the full name a struct was defined under
      def full_name_of(klass)
        @struct_names[klass]
      end

      # @param klass [::Class]
      # @param full [::String]
      # @return [void]
      def remember(klass, full)
        @struct_names[klass] = full
      end

      # Splits a named struct's class name into Avro name and namespace and checks every segment.
      #
      # @param klass [::Class] a named struct
      # @return [Array(::String, ::String, nil)] name and namespace (nil without a module)
      # @raise [::ArgumentError] for a segment Avro cannot name
      def self.split(klass)
        segments = klass.name.split('::')
        segments.each do |part|
          next if VALID.match?(part)

          raise ::ArgumentError, "FieldStruct::Avro: class #{klass.name} is named #{part.inspect}, " \
                                 'which Avro names can\'t be ([A-Za-z_][A-Za-z0-9_]*)'
        end
        [segments.last, segments.size > 1 ? segments[0...-1].join('.') : nil]
      end

      # @param label [::String] +Klass#field+
      # @param key [::String] the Avro field name
      # @return [void]
      # @raise [::ArgumentError] when Avro cannot use the name
      def self.check_field(label, key)
        return if VALID.match?(key)

        raise ::ArgumentError, "FieldStruct::Avro: field #{label} is named #{key.inspect}, " \
                               'which Avro names can\'t be ([A-Za-z_][A-Za-z0-9_]*)'
      end
    end
  end
end
