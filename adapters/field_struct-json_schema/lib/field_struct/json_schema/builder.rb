# frozen_string_literal: true

module FieldStruct
  module JSONSchema
    # Walks a struct class with +FieldStruct::Introspection+ and builds its schema (JS-B1..B17). One Builder builds
    # one document and is thrown away.
    class Builder
      # What a build produced.
      #
      # @!attribute [r] schema
      #   @return [::Hash{::String=>::Object}] the document
      # @!attribute [r] stamps
      #   @return [::Hash{::Class=>::Array<::Object>}] the stamp of every class the document covers
      # @!attribute [r] hooked
      #   @return [::Boolean] whether a type's +json_schema+ hook was asked
      Result = Struct.new(:schema, :stamps, :hooked)

      # Where in the struct tree a field sits, for error messages: +Holder#inner.x+.
      Spot = Struct.new(:prefix, :path) do
        # @return [::String]
        def label
          "#{prefix}#{path.join('.')}"
        end

        # @param name [::Symbol]
        # @return [Spot]
        def down(name)
          Spot.new(prefix, [*path, name])
        end
      end
      private_constant :Spot

      # @param root [::Class] a +FieldStruct::Base+ subclass
      # @param serialization [::Symbol]
      def initialize(root, serialization)
        @root = root
        @serialization = serialization
        @stamps = {}
        @hooked = false
        @defs = {}
        @inlining = [root]
      end

      # @return [Result]
      def build
        body = object_schema(@root, Spot.new("#{label_of(@root)}#", []))
        head = { '$schema' => DRAFT }
        head['title'] = @root.name if Introspection.named?(@root)
        document = head.merge(body)
        document['$defs'] = @defs unless @defs.empty?
        Result.new(document, @stamps, @hooked)
      end

      private

      def label_of(klass)
        klass.name || klass.inspect
      end

      # The object schema of +klass+ without $schema/title.
      def object_schema(klass, spot)
        @stamps[klass] ||= Stamp.of(klass, @serialization)
        properties = {}
        required = []
        Introspection.properties(klass, serialization: @serialization).each do |prop|
          properties[prop.key] = property_schema(prop.field, prop.node, spot.down(prop.field.name))
          required << prop.key if prop.field.required? && prop.field.default.nil?
        end
        schema = { 'type' => 'object', 'properties' => properties }
        schema['required'] = required unless required.empty?
        schema['additionalProperties'] = false if klass.unknown_attributes == :raise
        schema
      end

      def property_schema(field, node, spot)
        core = field_override(field, spot) || node_schema(node, spot)
        core = Nullable.field(core, field.type_instance) unless field.required?
        annotations(field).merge(core)
      end

      def annotations(field)
        notes = {}
        notes['description'] = field.description if field.description
        default = Defaults.for(field)
        notes['default'] = default unless default.equal?(Defaults::NONE) || field.sensitive?
        notes['x-sensitive'] = true if field.sensitive?
        notes
      end

      # The field's own json_schema: option, or nil when it has none.
      def field_override(field, spot)
        value = field.options[:json_schema]
        return nil if value.nil?

        Override.normalize(value) ||
          raise(::ArgumentError, "FieldStruct::JSONSchema.generate: the json_schema: option of #{spot.label} " \
                                 "must be a Hash or a boolean, got #{value.inspect}")
      end

      # The type's json_schema hook, or nil when the type has none or the hook declines.
      def hook_schema(type, spot)
        return nil unless type.respond_to?(:json_schema)

        @hooked = true
        name = "#{type.class.name || type.class.inspect}#json_schema"
        value = call_hook(type, name, spot)
        return nil if value.nil?

        Override.normalize(value) ||
          raise(::ArgumentError, "FieldStruct::JSONSchema.generate: #{name} (for #{spot.label}) " \
                                 "must be a Hash or a boolean, got #{value.inspect}")
      end

      def call_hook(type, name, spot)
        type.json_schema
      rescue ::StandardError => e
        raise ::ArgumentError, "FieldStruct::JSONSchema.generate: #{name} raised #{e.class} (for #{spot.label}): #{e.message}"
      end

      def node_schema(node, spot)
        hook_schema(node.type, spot) || plain_node_schema(node, spot)
      end

      def plain_node_schema(node, spot)
        case node
        when Introspection::ArrayNode then array_schema(node, spot)
        when Introspection::UnionNode then union_schema(node, spot)
        when Introspection::StructNode then struct_schema(node.klass, spot)
        else Scalar.call(node.type, node.options)
        end
      end

      def array_schema(node, spot)
        element = node.element
        return { 'type' => 'array' } if element.nil?

        { 'type' => 'array', 'items' => Nullable.call(node_schema(element, spot)) }
      end

      def union_schema(node, spot)
        members = node.members.map { |member| node_schema(member, spot) }.uniq
        members.any?(&:empty?) ? {} : { 'anyOf' => members }
      end

      def struct_schema(klass, spot)
        return { '$ref' => '#' } if klass.equal?(@root) && Introspection.named?(klass)
        return definition_ref(klass) if Introspection.named?(klass)

        inline_struct(klass, spot)
      end

      def definition_ref(klass)
        name = klass.name
        unless @defs.key?(name)
          @defs[name] = nil
          @defs[name] = { 'title' => name }.merge(object_schema(klass, Spot.new("#{name}#", [])))
        end
        { '$ref' => "#/$defs/#{name}" }
      end

      def inline_struct(klass, spot)
        if @inlining.include?(klass)
          raise ::ArgumentError, "FieldStruct::JSONSchema.generate(#{label_of(@root)}) cannot describe a recursive anonymous struct; " \
                                 'assign it to a constant'
        end

        @inlining.push(klass)
        begin
          object_schema(klass, spot)
        ensure
          @inlining.pop
        end
      end
    end
  end
end
