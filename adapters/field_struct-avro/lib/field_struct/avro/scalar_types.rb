# frozen_string_literal: true

module FieldStruct
  module Avro
    # Maps a scalar node to its Avro type (AV-B4..AV-B6, AV-B9).
    class ScalarTypes
      DATE = { 'type' => 'int', 'logicalType' => 'date' }.freeze
      private_constant :DATE

      # Checked in order, so a subclass wins: a String or Hash is the Avro type, a Symbol names the method that builds it.
      MAPPING = [
        [Types::Binary, 'bytes'], [Types::UUID, :uuid], [Types::String, 'string'], [Types::Value, 'string'],
        [Types::Boolean, 'boolean'], [Types::Integer, 'long'], [Types::Float, 'double'], [Types::BigDecimal, :decimal],
        [Types::Date, DATE], [Types::Time, :timestamp], [Types::DateTime, :timestamp], [Types::Symbol, :symbol]
      ].freeze
      private_constant :MAPPING

      # @param timestamp [::Symbol] the call's timestamp precision
      # @param names [Names] the schema's name claims (enums claim theirs)
      def initialize(timestamp, names)
        @timestamp = timestamp
        @names = names
      end

      # @param node [FieldStruct::Introspection::ScalarNode]
      # @param site [Site]
      # @param base [::String] the name an enum under this node takes
      # @return [::String, ::Hash] the Avro type
      # @raise [::ArgumentError] for a type with no mapping or options Avro cannot hold
      def call(node, site, base)
        _, mapped = MAPPING.find { |klass, _| node.type.is_a?(klass) }
        case mapped
        when nil then unmapped(node.type, site)
        when ::Symbol then send(mapped, node, site, base)
        else mapped.dup
        end
      end

      private

      def uuid(node, *)
        format = node.options[:format]
        return 'string' unless format.nil? || format == node.type.class.default_format

        { 'type' => 'string', 'logicalType' => 'uuid' }
      end

      def decimal(node, site, *)
        spec = Options.decimal(site.opts, node.options, node.type, site)
        return 'string' if spec.nil?

        { 'type' => 'bytes', 'logicalType' => 'decimal', 'precision' => spec[0], 'scale' => spec[1] }
      end

      def timestamp(_node, site, *)
        { 'type' => 'long', 'logicalType' => "timestamp-#{Options.timestamp(site.opts, @timestamp, site)}" }
      end

      def symbol(node, site, base)
        symbols = node.options[:enum]
        return 'string' unless symbols.is_a?(::Array) && !symbols.empty? && site.opts[:enum] != false

        names = symbols.map(&:to_s)
        return 'string' unless names.all? { |name| Names::VALID.match?(name) }

        enum(names, site, base)
      end

      def enum(names, site, base)
        type = { 'type' => 'enum', 'name' => base, 'symbols' => names }
        type['default'] = site.opts[:enum_default].to_s if site.opts.key?(:enum_default)
        full = site.frame.namespace ? "#{site.frame.namespace}.#{base}" : base
        status = @names.claim(full, type, 'an enum', 'rename one of the fields')
        status == :seen ? full : type
      end

      def unmapped(type, site)
        raise ::ArgumentError, "FieldStruct::Avro has no mapping for #{type.class.name || type.class.inspect} (#{site.where}); " \
                               'give the field avro: {type: …}'
      end
    end
  end
end
