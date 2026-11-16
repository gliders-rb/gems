# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Reads and validates the +proto: {number:}+ option of every field before anything is built (PB-B1, PB-B2).
    module Numbers
      # The usable range of a field number.
      # @return [::Range]
      RANGE = (1..536_870_911)
      # The range protobuf reserves for its own use.
      # @return [::Range]
      RESERVED = (19_000..19_999)
      # The keys a +proto:+ Hash may hold (PB-B2a).
      # @return [::Array<::Symbol>]
      KEYS = %i[number].freeze

      module_function

      # @param klass [::Class<FieldStruct::Base>]
      # @param properties [::Array<FieldStruct::Introspection::Property>]
      # @return [::Hash{::String=>::Integer}] number by property key, in declaration order
      # @raise [::ArgumentError] for an unusable, missing or duplicated number (in that order)
      def call(klass, properties)
        numbers = properties.to_h { |property| [property.key, read(klass, property.field)] }
        missing = numbers.select { |_, number| number.nil? }.keys
        unless missing.empty?
          raise ::ArgumentError,
                "#{klass}: give every field a protobuf field number, e.g. `proto: {number: 1}`; missing on #{missing.join(', ')}"
        end

        twice = numbers.values.tally.select { |_, count| count > 1 }.keys
        raise ::ArgumentError, "#{klass}: field numbers #{twice.join(', ')} are used twice" unless twice.empty?

        numbers
      end

      # @param klass [::Class]
      # @param field [FieldStruct::Field]
      # @return [::Integer, nil] nil when the field declares no number
      def read(klass, field)
        option = field.options[:proto]
        return nil if option.nil?

        unless option.is_a?(::Hash)
          raise ::ArgumentError, "#{klass}##{field.name}: proto: takes a Hash like {number: 1}, got #{option.inspect}"
        end

        check_keys(klass, field, option)
        number = option[:number]
        return nil if number.nil?
        return number if number.is_a?(::Integer) && RANGE.cover?(number) && !RESERVED.cover?(number)

        raise ::ArgumentError, "#{klass}##{field.name}: #{number.inspect} isn't a usable protobuf field number; " \
                               "use an Integer in #{RANGE}, outside #{RESERVED}"
      end

      # @param klass [::Class]
      # @param field [FieldStruct::Field]
      # @param option [::Hash{::Object=>::Object}]
      # @return [void]
      # @raise [::ArgumentError] for a key other than +number:+
      def check_keys(klass, field, option)
        unknown = option.keys.find { |key| !KEYS.include?(key) }
        return if unknown.nil?

        raise ::ArgumentError, "#{klass}##{field.name}: proto: has no key #{key_label(unknown)}#{key_hint(unknown)}; " \
                               "it takes #{KEYS.map { |key| "#{key}:" }.join(', ')}"
      end

      # @param key [::Object]
      # @return [::String] +number:+ for a Symbol, the inspected key otherwise
      def key_label(key) = key.is_a?(::Symbol) ? "#{key}:" : key.inspect

      # @param key [::Object]
      # @return [::String] the did-you-mean clause; a String spelled like a known key suggests the Symbol
      def key_hint(key)
        return " (did you mean #{key}:?)" if !key.is_a?(::Symbol) && KEYS.include?(key.to_s.to_sym)

        FieldStruct::Suggestion.clause(key, KEYS, sigil: '', suffix: ':')
      end
    end
  end
end
