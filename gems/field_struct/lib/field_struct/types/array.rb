# frozen_string_literal: true

module FieldStruct
  module Types
    # A list whose elements are all coerced by one element type. A refused element fails the whole array.
    class Array < Base
      # Index phrases name at most this many indexes.
      # @return [::Integer]
      MAX_INDEXES_SHOWN = 5

      # Raised for a lazy source on an array of mirrors with no +max_items:+; the setter names the field (FS-B169).
      # @api private
      class Unbounded < FieldStruct::Error; end

      NO_ELEMENT_OPTIONS = {}.freeze
      private_constant :NO_ELEMENT_OPTIONS

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          {
            of: option(type: [::Symbol, ::String, ::Class], required: true),
            element: option(type: ::Hash),
            max_items: option(type: ::Integer)
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
          check_max_items(options[:max_items])
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

        def check_max_items(limit)
          return if limit.nil? || limit >= 0

          raise ::ArgumentError, "max_items: on Array takes a whole number from 0, got #{limit}"
        end

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
      # @param max_items [::Integer, nil] how much of a lazy source an array of mirrors reads (FS-B169)
      # @return [::Array<::Object>, nil] a new Array
      # @raise [ArgumentError, TypeError, RangeError] when any element is refused (message names the indexes)
      def coerce(value, of_type: nil, element: nil, max_items: nil, **)
        coerce_with(value, of_type, element, max_items)
      end

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::Array<::Object>, nil]
      # @api private
      def coerce_positional(value, options)
        coerce_with(value, options[:of_type], options[:element], options[:max_items])
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

      def coerce_with(value, of_type, element, max_items)
        return nil if value.nil?
        raise ::ArgumentError, 'array coerce requires of_type:' if of_type.nil?

        type = of_type.is_a?(::Class) ? of_type.new : of_type
        value = source_items(value, type, max_items) unless value.is_a?(::Array)
        coerce_elements(value, type, element || NO_ELEMENT_OPTIONS)
      end

      # The items of a non-Array source for an array of mirrors: a loaded one whole, a lazy one up to one past
      # +max_items:+ (FS-B169).
      def source_items(value, type, max_items)
        raise ::TypeError, "expected Array, got #{value.class}" unless type.is_a?(Nested) && type.struct_class.mirror?
        return value.to_a if value.respond_to?(:loaded?) && value.loaded? == true
        raise ::TypeError, "expected Array, got #{value.class}" unless value.respond_to?(:first)
        raise Unbounded if max_items.nil?

        value.first(max_items + 1)
      end

      # Builds the result by index and the failure list only on a failure, so a clean Array costs one new Array.
      def coerce_elements(values, type, options)
        failures = nil
        positional = type.class.positional_coerce?
        result = ::Array.new(values.size) do |index|
          item = values[index]
          next nil if item.nil?

          begin
            if positional then type.coerce_positional(item, options)
            elsif options.empty? then type.coerce(item)
            else type.coerce(item, **options)
            end
          rescue ::ArgumentError, ::TypeError, ::RangeError => e
            (failures ||= []) << [index, e]
            nil
          end
        end
        raise_failures(failures) if failures
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
