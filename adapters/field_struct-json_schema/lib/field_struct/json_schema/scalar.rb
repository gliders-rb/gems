# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # The schema of a scalar type (JS-B8..B10) and the schema of a custom type without a hook (JS-B12).
    module Scalar
      T = FieldStruct::Types
      MAPPERS = [
        [T::Boolean, :boolean], [T::Integer, :integer], [T::Float, :float], [T::BigDecimal, :decimal],
        [T::DateTime, :datetime], [T::Time, :datetime], [T::Date, :date], [T::Symbol, :symbol],
        [T::String, :string], [T::Value, :value]
      ].freeze
      private_constant :MAPPERS

      module_function

      # @param type [FieldStruct::Types::Base]
      # @param options [::Hash{::Symbol=>::Object}] the options the value is checked with
      # @return [::Hash{::String=>::Object}]
      def call(type, options)
        _, mapper = MAPPERS.find { |klass, _| type.is_a?(klass) }
        mapper ? send(mapper, type, options) : { 'x-ruby-type' => ruby_type_names(type) }
      end

      # @param type [FieldStruct::Types::Base]
      # @return [::String]
      def ruby_type_names(type)
        [type.ruby_type].flatten.map { |klass| klass.name || klass.inspect }.join(' | ')
      end

      # @param range [::Range, ::Array, nil]
      # @return [::Hash{::String=>::Object}]
      def bounds(range)
        case range
        when ::Array then { 'enum' => range }
        when ::Range then range_bounds(range)
        else {}
        end
      end

      # @param range [::Range]
      # @return [::Hash{::String=>::Object}]
      def range_bounds(range)
        keys = {}
        keys['minimum'] = number(range.begin) if finite?(range.begin)
        keys[range.exclude_end? ? 'exclusiveMaximum' : 'maximum'] = number(range.end) if finite?(range.end)
        keys
      end

      # @param value [::Object]
      # @return [::Boolean]
      def finite?(value)
        !value.nil? && !(value.respond_to?(:infinite?) && value.infinite?)
      end

      # @param value [::Numeric]
      # @return [::Integer, ::Float]
      def number(value)
        value.is_a?(::Integer) || value.is_a?(::Float) ? value : value.to_f
      end

      # @return [::Hash{::String=>::Object}]
      def boolean(*) = { 'type' => 'boolean' }

      # @return [::Hash{::String=>::Object}]
      def integer(_type, options) = { 'type' => 'integer' }.merge!(bounds(options[:in]))

      # @return [::Hash{::String=>::Object}]
      def float(_type, options) = { 'type' => 'number' }.merge!(bounds(options[:in]))

      # @return [::Hash{::String=>::Object}]
      def decimal(*) = { 'type' => 'string', 'pattern' => DECIMAL_PATTERN }

      # @return [::Hash{::String=>::Object}]
      def value(*) = {}

      # @return [::Hash{::String=>::Object}]
      def datetime(_type, options) = temporal('date-time', options)

      # @return [::Hash{::String=>::Object}]
      def date(_type, options) = temporal('date', options)

      # @param name [::String]
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::Hash{::String=>::Object}]
      def temporal(name, options)
        format = options[:format]
        format.nil? || format == :iso8601 ? { 'type' => 'string', 'format' => name } : { 'type' => 'string' }
      end

      # @return [::Hash{::String=>::Object}]
      def symbol(_type, options)
        schema = { 'type' => 'string' }
        schema['enum'] = options[:enum].map(&:to_s) if options[:enum]
        schema
      end

      # @param type [FieldStruct::Types::String]
      # @param options [::Hash{::Symbol=>::Object}]
      # @return [::Hash{::String=>::Object}]
      def string(type, options)
        schema = { 'type' => 'string' }
        format = options[:format]
        schema.merge!(format_keys(type, format)) if format.is_a?(::Regexp)
        schema['enum'] = options[:enum] if options[:enum]
        schema
      end

      # @param type [FieldStruct::Types::String]
      # @param regexp [::Regexp]
      # @return [::Hash{::String=>::Object}]
      def format_keys(type, regexp)
        return { 'format' => 'uuid' } if type.is_a?(T::UUID) && regexp == T::UUID.default_format

        pattern = FieldStruct::JSONSchema.pattern_for(regexp)
        pattern ? { 'pattern' => pattern } : { 'x-ruby-pattern' => regexp.source }
      end
    end
  end
end
