# frozen_string_literal: true

module FieldStruct
  module Avro
    # Turns a struct instance into the Hash the avro gem writes (AV-B19..AV-B24).
    class DatumWriter
      # The node classes of the introspection walk.
      NODES = FieldStruct::Introspection

      # @param serialization [::Symbol]
      # @param timestamp [::Symbol] the call's timestamp precision
      def initialize(serialization, timestamp)
        @serialization = serialization
        @timestamp = timestamp
      end

      # @param instance [FieldStruct::Base]
      # @param trail [Trail]
      # @return [::Hash{::String=>::Object}]
      def struct(instance, trail)
        Cache.properties(instance.class, @serialization).to_h do |prop|
          [prop.key, property(instance.public_send(prop.field.name), prop, trail)]
        end
      end

      private

      def property(value, prop, trail)
        field = prop.field
        opts = Options.read(field) { trail.label(field) }
        site = Spot.new(trail, field, opts)
        override = Options.override(opts)
        return nil if value.nil?
        return overridden(value, prop.node, Options.stringify(override), site) unless override.nil?

        node_value(value, prop.node, site)
      end

      def node_value(value, node, site)
        return nil if value.nil?

        case node
        when NODES::ScalarNode then scalar(value, node, site)
        when NODES::ArrayNode then array(value, node, site)
        when NODES::StructNode then nested(value, node.klass, site)
        else union(value, node, site)
        end
      end

      def array(value, node, site)
        element = node.element
        return raw(value, site) if element.nil? || !value.is_a?(::Array)

        value.map { |item| node_value(item, element, site) }
      end

      def nested(value, klass, site)
        return value unless value.is_a?(klass)

        struct(value, site.enter(klass))
      end

      def scalar(value, node, site)
        case node.type
        when Types::BigDecimal then decimal(value, node, site)
        when Types::Time, Types::DateTime then time(value, site)
        when Types::Symbol then value.to_s
        when Types::Value then ValueJson.dump(value)
        else value
        end
      end

      def decimal(value, node, site)
        spec = Options.decimal(site.opts, node.options, node.type, site)
        spec.nil? && value.is_a?(::BigDecimal) ? value.to_s('F') : value
      end

      def time(value, site)
        value = value.to_time if value.is_a?(::DateTime)
        return value unless value.is_a?(::Time)

        precision = Options.timestamp(site.opts, @timestamp, site)
        check_precision(value, precision, site)
        value
      end

      def check_precision(time, precision, site)
        return if (time.nsec % Options::UNITS.fetch(precision)).zero?

        shown = site.sensitive? ? 'a sensitive time' : time.iso8601(9)
        raise ::ArgumentError, "FieldStruct::Avro: #{site.label} is #{shown}, which has more precision than " \
                               "timestamp-#{precision}; round it, or use timestamp: :nanos"
      end

      def union(value, node, site)
        members = node.members.partition { |member| !value_member?(member) }.flatten(1)
        member = members.find { |candidate| matches?(candidate, value) }
        member ? node_value(value, member, site) : value
      end

      def value_member?(member)
        member.is_a?(NODES::ScalarNode) && member.type.is_a?(Types::Value)
      end

      def matches?(member, value)
        return value.is_a?(member.klass) if member.is_a?(NODES::StructNode)

        Array(member.type.ruby_type).any? { |klass| value.is_a?(klass) }
      end

      def overridden(value, node, type, site)
        return ValueJson.dump(value) if node.is_a?(NODES::ScalarNode) && node.type.is_a?(Types::Value) && Options.string_type?(type)

        raw(value, site)
      end

      def raw(value, site)
        case value
        when ::Symbol then value.to_s
        when ::Hash then value.to_h { |key, item| [raw(key, site), raw(item, site)] }
        when ::Array then value.map { |item| raw(item, site) }
        when FieldStruct::Base then struct(value, site.enter(value.class))
        else value
        end
      end
    end
  end
end
