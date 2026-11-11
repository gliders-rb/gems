# frozen_string_literal: true

module FieldStruct
  module Avro
    # The one interpretation of a field's +avro:+ option, shared by the schema builder and the datum converters
    # so a schema never promises what the datum does not write (AV-I2).
    module Options
      # Nanoseconds in one unit of each timestamp precision.
      # @return [::Hash{::Symbol=>::Integer}]
      UNITS = { nanos: 1, micros: 1_000, millis: 1_000_000 }.freeze

      # Default decimal precision.
      # @return [::Integer]
      DEFAULT_PRECISION = 38

      # The read options per Field object (by identity), so a field's +avro:+ is symbolized once, not per call.
      # Changing a field's options in place is not noticed (AV-B53); redeclaring the field makes a new Field.
      READ = ::ObjectSpace::WeakMap.new
      private_constant :READ

      # The result for a field with no +avro:+ option.
      NONE = {}.freeze
      private_constant :NONE

      module_function

      # The field's +avro:+ options as a frozen Hash with Symbol keys, read once per Field object (AV-B53).
      #
      # @param field [FieldStruct::Field]
      # @yieldreturn [::String] +Klass#field+, built only for the error
      # @return [::Hash{::Symbol=>::Object}]
      # @raise [::ArgumentError] when +avro:+ is not a Hash
      def read(field)
        value = field.options[:avro]
        return NONE if value.nil?

        cached = READ[field]
        return cached if cached

        raise ::ArgumentError, not_a_hash(yield, value) unless value.is_a?(::Hash)

        READ[field] = value.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }.freeze
      end

      # @param label [::String]
      # @param value [::Object]
      # @return [::String]
      def not_a_hash(label, value)
        "FieldStruct::Avro (#{label}) avro: takes a Hash of options, like avro: {type: 'string'}, got #{value.inspect}"
      end

      # @param opts [::Hash{::Symbol=>::Object}]
      # @return [::Object, nil] the +type:+ override, or nil for none
      def override(opts)
        opts[:type]
      end

      # The options that also apply to array elements and union members (everything but +type:+).
      #
      # @param opts [::Hash{::Symbol=>::Object}]
      # @return [::Hash{::Symbol=>::Object}]
      def nested(opts)
        opts.except(:type)
      end

      # The timestamp precision of a field: its own +avro: {timestamp:}+ or the call's.
      #
      # @param opts [::Hash{::Symbol=>::Object}]
      # @param default [::Symbol] the call's precision
      # @param site [Site, Spot] the field being handled; its label is built only for the error
      # @return [::Symbol]
      # @raise [::ArgumentError] for a precision that is not in +TIMESTAMPS+
      def timestamp(opts, default, site)
        value = opts[:timestamp]
        return default if value.nil?
        return value if TIMESTAMPS.include?(value)

        raise ::ArgumentError,
              "FieldStruct::Avro (#{site.label}) avro: {timestamp:} must be one of #{TIMESTAMPS.inspect}, got #{value.inspect}"
      end

      # The +[precision, scale]+ of a decimal field, or nil when it is written as a string (AV-B5).
      #
      # @param opts [::Hash{::Symbol=>::Object}] the field's +avro:+ options
      # @param node_options [::Hash{::Symbol=>::Object}] the options the value is checked with
      # @param type [FieldStruct::Types::Base] the decimal type instance
      # @param where [Site, Spot] the field being handled; its label is built only for the error
      # @return [::Array(::Integer, ::Integer), nil]
      # @raise [::ArgumentError] for a precision or scale Avro cannot hold
      def decimal(opts, node_options, type, where)
        scale = decimal_scale(opts, node_options, type)
        return nil if scale.nil?

        precision = opts[:precision].nil? ? DEFAULT_PRECISION : opts[:precision]
        check_integers(precision, scale, where)
        scale = 0 if scale.negative?
        check_range(precision, scale, where)
        [precision, scale]
      end

      # @param precision [::Object]
      # @param scale [::Object]
      # @param where [Site, Spot]
      # @return [void]
      def check_integers(precision, scale, where)
        return if precision.is_a?(::Integer) && scale.is_a?(::Integer)

        decimal_error(where, "decimal precision and scale must be integers, got #{precision.inspect} and #{scale.inspect}")
      end

      # @param precision [::Integer]
      # @param scale [::Integer]
      # @param where [Site, Spot]
      # @return [void]
      def check_range(precision, scale, where)
        decimal_error(where, "precision #{precision} must be at least 1") if precision < 1
        decimal_error(where, "scale #{scale} is more than precision #{precision}; raise avro: {precision:}") if scale > precision
      end

      # @param opts [::Hash{::Symbol=>::Object}]
      # @param node_options [::Hash{::Symbol=>::Object}]
      # @param type [FieldStruct::Types::Base]
      # @return [::Object, nil]
      def decimal_scale(opts, node_options, type)
        return opts[:scale] unless opts[:scale].nil?
        return node_options[:round] unless node_options[:round].nil?

        type.class.respond_to?(:default_round) ? type.class.default_round : nil
      end

      # @param where [Site, Spot]
      # @param message [::String]
      # @return [void]
      def decimal_error(where, message)
        raise ::ArgumentError, "FieldStruct::Avro can't describe #{where.label}: #{message}"
      end

      # Symbols become Strings, deeply, in Hashes and Arrays (an +avro: {type:}+ override as written to the schema).
      #
      # @param value [::Object]
      # @return [::Object]
      def stringify(value)
        case value
        when ::Symbol then value.to_s
        when ::Hash then value.to_h { |key, item| [stringify(key), stringify(item)] }
        when ::Array then value.map { |item| stringify(item) }
        else value
        end
      end

      # Whether an (already stringified) override is a plain Avro string, or a union of null and string.
      #
      # @param type [::Object]
      # @return [::Boolean]
      def string_type?(type)
        case type
        when ::String then type == 'string'
        when ::Hash then type['type'] == 'string' && !type.key?('logicalType')
        when ::Array then string_union?(type)
        else false
        end
      end

      # @param types [::Array<::Object>]
      # @return [::Boolean] whether the union is only null and string types, with at least one string
      def string_union?(types)
        types.any? { |item| string_type?(item) } && types.all? { |item| item == 'null' || string_type?(item) }
      end
    end
  end
end
