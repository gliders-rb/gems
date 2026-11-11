# frozen_string_literal: true

module FieldStruct
  module Avro
    # A copy of a schema Hash without the fields the writer lacked, so the avro gem needs no default for them and
    # the datum has no key for them: the loader then lets +new+ apply the field_struct default (AV-B40).
    class Projection
      # @param schema [::Hash] a schema Hash (never mutated)
      # @param lacking [::Hash{::String=>::Array<::String>}] record full name to the field names to leave out
      # @return [::Hash] the projected copy
      def self.call(schema, lacking)
        new(lacking).fragment(schema, nil)
      end

      # @param lacking [::Hash{::String=>::Array<::String>}]
      def initialize(lacking)
        @lacking = lacking
      end

      # @param value [::Object] a schema fragment
      # @param namespace [::String, nil] the enclosing namespace
      # @return [::Object] the fragment, projected
      def fragment(value, namespace)
        case value
        when ::Array then value.map { |item| fragment(item, namespace) }
        when ::Hash then hash(value, namespace)
        else value
        end
      end

      private

      def hash(node, namespace)
        case node['type']
        when 'record' then record(node, namespace)
        when 'array' then node.merge('items' => fragment(node['items'], namespace))
        when 'map' then node.merge('values' => fragment(node['values'], namespace))
        when ::Hash, ::Array then node.merge('type' => fragment(node['type'], namespace))
        else node
        end
      end

      def record(node, namespace)
        full, inner = names(node, namespace)
        left_out = @lacking.fetch(full, [])
        fields = node['fields'].reject { |field| left_out.include?(field['name']) }
        node.merge('fields' => fields.map { |field| field.merge('type' => fragment(field['type'], inner)) })
      end

      def names(node, namespace)
        name = node['name']
        return [name, name.rpartition('.').first] if name.include?('.')

        space = node.key?('namespace') ? node['namespace'] : namespace
        [space ? "#{space}.#{name}" : name, space]
      end
    end
  end
end
