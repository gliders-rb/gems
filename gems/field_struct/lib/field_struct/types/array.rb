# frozen_string_literal: true

module FieldStruct
  module Types
    # A list whose elements are all coerced by one element type. A refused element fails the whole array.
    class Array < Base
      # Index phrases name at most this many indexes.
      # @return [::Integer]
      MAX_INDEXES_SHOWN = 5

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
          'array field requires an `of:` option naming the element type'
        end

        # Replaces +of:+ by +of_type:+ (a type class, or a Nested instance for a struct) and validates +element:+.
        #
        # @param options [::Hash{::Symbol=>::Object}]
        # @param registry [FieldStruct::Registry]
        # @param field_name [::Symbol]
        # @return [::Hash{::Symbol=>::Object}]
        # @raise [ArgumentError, KeyError] for an unknown element type or bad element options
        def resolve_options(options, registry:, field_name:)
          of_type = element_type_for(options[:of], registry)
          resolved = { of_type: of_type }.merge(options.except(:of, :element))
          element = ElementOptions.call(element_class(of_type), options[:element], registry: registry, field_name: field_name)
          element ? resolved.merge(element: element) : resolved
        end

        # @param of_type [::Class, FieldStruct::Types::Base] a type class or a Nested instance
        # @return [::Class] the element type's class
        def element_class(of_type)
          of_type.is_a?(::Class) ? of_type : of_type.class
        end

        # Renders which elements a message is about.
        #
        # @param indexes [::Array<::Integer>] 0-based
        # @return [::String] +element at index 1+ or +elements at index 1, 4+ (five at most, then +and N more+)
        def elements_at(indexes)
          return "element at index #{indexes.first}" if indexes.size == 1

          shown = indexes.first(MAX_INDEXES_SHOWN).join(', ')
          extra = indexes.size - MAX_INDEXES_SHOWN
          "elements at index #{shown}#{" and #{extra} more" if extra.positive?}"
        end

        private

        def element_type_for(of, registry)
          klass = of.is_a?(::Class) ? of : registry.lookup(of)
          return Nested.new(klass) if klass <= FieldStruct::Base
          return klass if klass <= Types::Base

          raise ::ArgumentError, "#{klass.inspect} is not a FieldStruct type (subclass FieldStruct::Types::Base)"
        end
      end

      # @param value [::Object]
      # @param of_type [::Class, FieldStruct::Types::Base, nil] element type (a class, or a Nested instance)
      # @param element [::Hash{::Symbol=>::Object}, nil] options handed to each element's coerce
      # @return [::Array<::Object>, nil] a new Array
      # @raise [ArgumentError, TypeError, RangeError] when any element is refused (message names the indexes)
      def coerce(value, of_type: nil, element: nil, **)
        return nil if value.nil?
        raise ::ArgumentError, 'array coerce requires of_type:' if of_type.nil?
        raise ::TypeError, "expected Array, got #{value.class}" unless value.is_a?(::Array)

        coerce_elements(value, of_type.is_a?(::Class) ? of_type.new : of_type, element || {})
      end

      # @param value [::Object]
      # @return [Boolean] true for nil and the empty Array
      def missing?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      # @return [::Class]
      def ruby_type
        ::Array
      end

      # The field-level message for elements that break +element:+ restrictions.
      #
      # @param indexes [::Array<::Integer>] the offending 0-based indexes
      # @return [::String]
      def self.invalid_elements_message(indexes)
        "#{elements_at(indexes)} #{indexes.size == 1 ? 'is' : 'are'} invalid"
      end

      private

      def coerce_elements(values, type, options)
        failures = []
        result = values.each_with_index.map do |item, index|
          next nil if item.nil?

          begin
            type.coerce(item, **options)
          rescue ::ArgumentError, ::TypeError, ::RangeError => e
            failures << [index, e]
            nil
          end
        end
        raise_failures(failures) unless failures.empty?
        result
      end

      def raise_failures(failures)
        indexes = failures.map(&:first)
        first = failures.first.last
        phrase = self.class.elements_at(indexes)
        phrase += " (index #{indexes.first} shown)" if indexes.size > 1
        error = first.class.new("#{phrase}: #{first.message}")
        raise error, cause: first.cause
      end
    end
  end
end
