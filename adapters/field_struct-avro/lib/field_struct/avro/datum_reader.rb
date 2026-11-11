# frozen_string_literal: true

module FieldStruct
  module Avro
    # Builds a struct from the Hash the avro gem read (AV-B25..AV-B29).
    class DatumReader
      # The node classes of the introspection walk.
      NODES = FieldStruct::Introspection

      # @param serialization [::Symbol]
      def initialize(serialization)
        @serialization = serialization
      end

      # @param klass [::Class]
      # @param datum [::Hash{::String=>::Object}]
      # @param trail [Trail]
      # @return [FieldStruct::Base]
      def struct(klass, datum, trail)
        attributes = {}
        Cache.properties(klass, @serialization).each do |prop|
          attributes[prop.field.name] = property(datum[prop.key], prop, trail) if datum.key?(prop.key)
        end
        klass.new(attributes)
      end

      private

      def property(value, prop, trail)
        field = prop.field
        opts = Options.read(field) { trail.label(field) }
        spot = Spot.new(trail, field, opts)
        override = Options.override(opts)
        return nil if value.nil?
        return overridden(value, prop.node, Options.stringify(override), spot) unless override.nil?

        node_value(value, prop.node, spot)
      end

      def node_value(value, node, spot)
        return nil if value.nil?

        case node
        when NODES::ScalarNode then scalar(value, node, spot)
        when NODES::ArrayNode then array(value, node, spot)
        when NODES::StructNode then nested(value, node.klass, spot)
        else union(value, node, spot)
        end
      end

      def array(value, node, spot)
        element = node.element
        return value if element.nil? || !value.is_a?(::Array)

        value.map { |item| node_value(item, element, spot) }
      end

      def nested(value, klass, spot)
        value.is_a?(::Hash) ? struct(klass, value, spot.enter(klass)) : value
      end

      def scalar(value, node, spot)
        case node.type
        when Types::Time, Types::DateTime then Zone.apply(value, node.options[:zone])
        when Types::Symbol then symbol(value, node, spot)
        when Types::Value then value.is_a?(::String) ? ValueJson.load(value, spot) : value
        else value
        end
      end

      def symbol(value, node, spot)
        symbols = node.options[:enum]
        return value unless symbols.is_a?(::Array) && (value.is_a?(::String) || value.is_a?(::Symbol))
        return value if symbols.any? { |symbol| symbol.to_s == value.to_s }
        return spot.opts[:enum_default].to_s if spot.opts.key?(:enum_default)

        unknown_symbol(value, spot)
      end

      def unknown_symbol(value, spot)
        shown = spot.sensitive? ? 'a sensitive symbol' : value.to_sym.inspect
        raise ::ArgumentError, "FieldStruct::Avro: #{spot.label} is #{shown}, which isn't one of the field's enum symbols; " \
                               'give the reader avro: {enum_default:} to read new ones'
      end

      def union(value, node, spot)
        case value
        when ::Hash then union_struct(value, node, spot)
        when ::String then union_string(value, node, spot)
        else value
        end
      end

      def union_struct(value, node, spot)
        keys = value.keys.sort
        member = node.members.grep(NODES::StructNode).find do |candidate|
          Cache.properties(candidate.klass, @serialization).map(&:key).sort == keys
        end
        member ? nested(value, member.klass, spot) : value
      end

      def union_string(value, node, spot)
        value_member = node.members.any? { |member| member.is_a?(NODES::ScalarNode) && member.type.is_a?(Types::Value) }
        value_member ? ValueJson.load(value, spot) : value
      end

      def overridden(value, node, type, spot)
        case node
        when NODES::StructNode then nested(value, node.klass, spot)
        when NODES::ArrayNode then overridden_array(value, node, spot)
        when NODES::ScalarNode then overridden_scalar(value, node, type, spot)
        else value
        end
      end

      def overridden_array(value, node, spot)
        element = node.element
        return value unless value.is_a?(::Array) && element.is_a?(NODES::StructNode)

        value.map { |item| nested(item, element.klass, spot) }
      end

      def overridden_scalar(value, node, type, spot)
        return Zone.apply(value, node.options[:zone]) if value.is_a?(::Time)
        return ValueJson.load(value, spot) if node.type.is_a?(Types::Value) && value.is_a?(::String) && Options.string_type?(type)

        value
      end
    end
  end
end
