# frozen_string_literal: true

module FieldStruct
  module Types
    # A map from String keys to values of one type (FS-B79a). A refused key or value fails the whole map; no message names a key.
    class Hash < Base
      NO_VALUE_OPTIONS = {}.freeze
      private_constant :NO_VALUE_OPTIONS

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          {
            of: option(type: [::Symbol, ::String, ::Class], required: true),
            element: option(type: ::Hash)
          }
        end

        # @param _key [::Symbol]
        # @return [::String]
        def required_option_message(_key)
          'hash field requires an `of:` option naming the value type'
        end

        # Replaces +of:+ by +of_type:+ (a type class, or a Nested instance for a struct) and validates +element:+.
        #
        # @param options [::Hash{::Symbol=>::Object}]
        # @param registry [FieldStruct::Registry]
        # @param field_name [::Symbol]
        # @return [::Hash{::Symbol=>::Object}]
        # @raise [ArgumentError, KeyError] for an unknown value type or bad value options
        def resolve_options(options, registry:, field_name:)
          of_type = Types::Array.send(:element_type_for, options[:of], registry)
          resolved = { of_type: of_type }.merge(options.except(:of, :element))
          element = ElementOptions.call(Types::Array.element_class(of_type), options[:element],
                                        registry: registry, field_name: field_name, kind: 'hash')
          element ? resolved.merge(element: element) : resolved
        end

        # The field-level message for values that break +element:+ restrictions; it names no key.
        #
        # @param count [::Integer] how many values failed
        # @return [::String]
        def invalid_entries_message(count)
          count == 1 ? '1 entry is invalid' : "#{count} entries are invalid"
        end
      end

      # @param value [::Object]
      # @param of_type [::Class, FieldStruct::Types::Base, nil] the value type (a class, or a Nested instance)
      # @param element [::Hash{::Symbol=>::Object}, nil] options handed to each value's coerce
      # @return [::Hash{::String=>::Object}, nil] a new Hash with String keys
      # @raise [ArgumentError, TypeError, RangeError] when a key or any value is refused (the message names no key)
      def coerce(value, of_type: nil, element: nil, **)
        coerce_with(value, of_type, element)
      end

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::Hash{::String=>::Object}, nil]
      # @api private
      def coerce_positional(value, options)
        coerce_with(value, options[:of_type], options[:element])
      end

      # @param value [::Object]
      # @return [Boolean] true for nil and the empty Hash
      def missing?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      # @return [::Class]
      def ruby_type
        ::Hash
      end

      private

      # @param value [::Object]
      # @param of_type [::Class, FieldStruct::Types::Base, nil]
      # @param element [::Hash{::Symbol=>::Object}, nil]
      # @return [::Hash{::String=>::Object}, nil]
      def coerce_with(value, of_type, element)
        return nil if value.nil?
        raise ::ArgumentError, 'hash coerce requires of_type:' if of_type.nil?
        raise ::TypeError, "expected Hash, got #{value.class}" unless value.is_a?(::Hash)

        coerce_entries(value, of_type.is_a?(::Class) ? of_type.new : of_type, element || NO_VALUE_OPTIONS)
      end

      # @param entries [::Hash{::Object=>::Object}]
      # @param type [FieldStruct::Types::Base]
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::Hash{::String=>::Object}]
      def coerce_entries(entries, type, options)
        failures = nil
        positional = type.class.positional_coerce?
        result = {}
        entries.each do |key, item|
          name = string_key(key)
          result[name] = begin
            item.nil? ? nil : coerce_value(type, item, options, positional)
          rescue ::ArgumentError, ::TypeError, ::RangeError => e
            (failures ||= []) << e
            nil
          end
        end
        raise_failures(failures) if failures
        result
      end

      # @param key [::Object]
      # @return [::String]
      def string_key(key)
        return key if key.is_a?(::String)
        return key.to_s if key.is_a?(::Symbol)

        raise ::TypeError, "hash keys must be Strings or Symbols, got #{key.class}"
      end

      # @param type [FieldStruct::Types::Base]
      # @param item [::Object]
      # @param options [::Hash{::Symbol=>::Object}]
      # @param positional [Boolean]
      # @return [::Object]
      def coerce_value(type, item, options, positional)
        if positional then type.coerce_positional(item, options)
        elsif options.empty? then type.coerce(item)
        else type.coerce(item, **options)
        end
      end

      # @param failures [::Array<::Exception>]
      # @return [void]
      def raise_failures(failures)
        first = failures.first
        phrase = failures.size == 1 ? 'value of 1 entry' : "values of #{failures.size} entries (first shown)"
        raise first.class.new("#{phrase}: #{first.message}"), cause: first.cause
      end
    end
  end
end
