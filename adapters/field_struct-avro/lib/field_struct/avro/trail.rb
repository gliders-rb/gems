# frozen_string_literal: true

module FieldStruct
  module Avro
    # Where a conversion is: the nearest named struct, the field path inside anonymous structs below it, and
    # whether any field on the way is sensitive. Messages name fields by it and never echo a sensitive value (AV-I4).
    class Trail
      # @return [::String] the nearest named struct's name
      attr_reader :base
      # @return [::Array<::Symbol>] field names below the named struct
      attr_reader :path
      # @return [::Boolean] whether a field above is sensitive
      attr_reader :sensitive

      # @param klass [::Class]
      # @return [Trail] the trail at the root struct
      def self.root(klass)
        new(klass.name || klass.inspect, [], false)
      end

      # @param base [::String]
      # @param path [::Array<::Symbol>]
      # @param sensitive [::Boolean]
      def initialize(base, path, sensitive)
        @base = base
        @path = path
        @sensitive = sensitive
        freeze
      end

      # The trail inside a struct held by a field.
      #
      # @param klass [::Class] the struct held
      # @param field [FieldStruct::Field] the field that holds it
      # @return [Trail]
      def enter(klass, field)
        sensitive = @sensitive || field.sensitive?
        return Trail.new(klass.name, [], sensitive) if FieldStruct::Introspection.named?(klass)

        Trail.new(@base, [*@path, field.name], sensitive)
      end

      # @param field [FieldStruct::Field]
      # @return [::String] +Klass#field+ (or +Holder#inner.field+ inside an anonymous struct)
      def label(field)
        "#{@base}##{[*@path, field.name].join('.')}"
      end

      # @param field [FieldStruct::Field]
      # @return [::Boolean] whether the field, or anything above it, is sensitive
      def sensitive?(field)
        @sensitive || field.sensitive?
      end
    end
  end
end
