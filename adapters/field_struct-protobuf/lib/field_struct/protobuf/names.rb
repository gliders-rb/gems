# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Package, message, file and full names of a struct class (PB-B4, section 3).
    module Names
      module_function

      # @param word [::String] a constant name segment
      # @return [::String] the segment underscored (+XMLThing+ gives +xml_thing+)
      def underscore(word)
        word.gsub(/(?<=[a-z\d])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/, '_').downcase
      end

      # @param klass [::Class]
      # @return [::String] the module path underscored and joined with dots; empty for a top-level class
      def package(klass)
        segments_of(klass).first(segments_of(klass).size - 1).map { underscore(_1) }.join('.')
      end

      # @param klass [::Class]
      # @return [::String] the last constant segment
      def message_name(klass)
        segments_of(klass).last
      end

      # @param klass [::Class]
      # @return [::String] a leading dot, the package and the message name
      def full_name(klass)
        [package(klass), message_name(klass)].reject(&:empty?).join('.').prepend('.')
      end

      # @param klass [::Class]
      # @return [::String] +field_struct/<underscored path>.proto+
      def file_name(klass)
        path = segments_of(klass).map { underscore(_1) }
        File.join('field_struct', "#{path.join('/')}.proto")
      end

      def segments_of(klass)
        klass.name.split('::')
      end
    end
  end
end
