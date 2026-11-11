# frozen_string_literal: true

module FieldStruct
  module Avro
    # A record being built: its struct class, Avro name, effective namespace and trail.
    Frame = Struct.new(:klass, :name, :namespace, :trail) do
      # @return [::String] the struct as errors name it
      def class_label
        klass.name || klass.inspect
      end
    end

    # One field being mapped: the record around it, the field, its Avro name, its +avro:+ options and its label.
    Site = Struct.new(:frame, :field, :key, :opts, :label) do
      # @return [::String] +Klass#field+ plus the Avro name, for the unmappable-type error
      def where
        "#{label} (Avro #{frame.name}_#{key})"
      end
    end

    # One field being converted: the trail of the struct around it, the field and its +avro:+ options.
    Spot = Struct.new(:trail, :field, :opts) do
      # @return [::String] +Klass#field+
      def label
        trail.label(field)
      end

      # @return [::Boolean] whether the field, or anything above it, is sensitive
      def sensitive?
        trail.sensitive?(field)
      end

      # @param klass [::Class] a struct held by the field
      # @return [Trail] the trail inside it
      def enter(klass)
        trail.enter(klass, field)
      end
    end
  end
end
