# frozen_string_literal: true

require_relative 'site'

module FieldStruct
  module Avro
    # Builds the Avro record schema of a struct class by walking it with FieldStruct::Introspection (AV-B4..AV-B30).
    class SchemaBuilder
      # @param klass [::Class] a named struct class
      # @param serialization [::Symbol]
      # @param timestamp [::Symbol]
      # @return [Entry]
      # @raise [::ArgumentError] for anything the schema cannot hold
      def self.entry(klass, serialization, timestamp)
        new(klass, serialization, timestamp).entry
      end

      # @param klass [::Class]
      # @param serialization [::Symbol]
      # @param timestamp [::Symbol]
      def initialize(klass, serialization, timestamp)
        @klass = klass
        @serialization = serialization
        @names = Names.new
        @scalars = ScalarTypes.new(timestamp, @names)
        @unions = UnionRules.new(serialization)
        @walked = []
        @stamps = []
        @building = {}
      end

      # @return [Entry]
      def entry
        Check.named!(@klass)
        hash = root
        check_serialization
        Entry.new(hash, parse(hash), @stamps)
      end

      private

      def root
        name, namespace = Names.split(@klass)
        full = [namespace, name].compact.join('.')
        @names.claim(full, @klass, @klass.name, "put #{@klass} in a module")
        @names.remember(@klass, full)
        record(@klass, name, namespace, Trail.root(@klass), explicit_namespace: namespace)
      end

      def record(klass, name, namespace, trail, explicit_namespace: nil)
        stamp(klass)
        frame = Frame.new(klass, name, namespace, trail)
        @building[klass] = true
        fields = FieldStruct::Introspection.properties(klass, serialization: @serialization).map { |prop| field(frame, prop) }
        @building.delete(klass)
        head = { 'type' => 'record', 'name' => name }
        head['namespace'] = explicit_namespace if explicit_namespace
        head.merge('fields' => fields)
      end

      def stamp(klass)
        return if @walked.include?(klass)

        @walked << klass
        @stamps << Stamp.of(klass, @serialization)
      end

      def field(frame, prop)
        field = prop.field
        label = frame.trail.label(field)
        Names.check_field(label, prop.key)
        site = Site.new(frame, field, prop.key, Options.read(field) { label }, label)
        override = Options.override(site.opts)
        type = override.nil? ? map(site, prop.node, "#{frame.name}_#{prop.key}") : Options.stringify(override)
        field_hash(site, type)
      end

      def field_hash(site, type)
        field = site.field
        hash = { 'name' => site.key }
        hash['doc'] = field.description if field.description
        hash['type'], default = typed(field, type)
        hash['default'] = default unless default.equal?(Defaults::NONE)
        hash['x-fs-sensitive'] = true if field.sensitive?
        hash
      end

      def typed(field, type)
        literal = Defaults.literal(field, type)
        return [type, literal] if field.required?
        return [nullable(type), nil] if literal.equal?(Defaults::NONE)

        [null_last(type), literal]
      end

      def null_last(type)
        type.is_a?(::Array) ? (type - ['null']) + ['null'] : [type, 'null']
      end

      def nullable(type)
        type.is_a?(::Array) ? ['null', *(type - ['null'])] : ['null', type]
      end

      def map(site, node, base)
        case node
        when FieldStruct::Introspection::ScalarNode then @scalars.call(node, site, base)
        when FieldStruct::Introspection::ArrayNode then array(site, node, base)
        when FieldStruct::Introspection::UnionNode then union(site, node, base)
        else struct(site, node.klass, base)
        end
      end

      def array(site, node, base)
        element = node.element
        if element.nil?
          raise ::ArgumentError, "FieldStruct::Avro can't describe #{site.label}: an array of arrays or unions records no element type"
        end

        { 'type' => 'array', 'items' => nullable(map(site, element, base)) }
      end

      def union(site, node, base)
        types = node.members.each_with_index.map { |member, index| map(site, member, "#{base}_#{index}") }
        classes = node.members.grep(FieldStruct::Introspection::StructNode).map(&:klass)
        @unions.check_shadowing(classes, site.label)
        @unions.order(types, site.frame, site.label)
      end

      def struct(site, klass, base)
        named = FieldStruct::Introspection.named?(klass)
        recursive!(site, klass) unless named
        return reference(site, klass) if named && @names.full_name_of(klass)

        define(site, klass, named, base)
      end

      def define(site, klass, named, base)
        name, namespace = named ? Names.split(klass) : [base, nil]
        effective = namespace || site.frame.namespace
        full = effective ? "#{effective}.#{name}" : name
        return reference(site, klass) if @names.claim(full, klass, struct_label(klass, named), fix(klass, named)) == :seen

        @names.remember(klass, full)
        record(klass, name, effective, site.frame.trail.enter(klass, site.field), explicit_namespace: namespace)
      end

      def struct_label(klass, named)
        named ? klass.name : 'an anonymous struct'
      end

      def fix(klass, named)
        named ? "put #{klass} in a module" : 'rename one of the fields'
      end

      def recursive!(site, klass)
        return unless @building[klass]

        raise ::ArgumentError, "FieldStruct::Avro cannot describe a recursive anonymous struct (at #{site.label}); assign it to a constant"
      end

      def reference(site, klass)
        full = @names.full_name_of(klass)
        check_bare(site, klass, full) if FieldStruct::Introspection.named?(klass)
        full
      end

      def check_bare(site, klass, full)
        namespace = site.frame.namespace
        return if full.include?('.') || namespace.nil?

        raise ::ArgumentError, "FieldStruct::Avro: #{klass} has no namespace and is used inside #{site.frame.class_label} " \
                               "(Avro namespace #{namespace}), where Avro would read #{full} as #{namespace}.#{full}; " \
                               "put #{klass} in a module"
      end

      def check_serialization
        return if @serialization == :avro || @walked.any? { |klass| klass.metadata.serializations.key?(@serialization) }

        declared = ([:avro] + @walked.flat_map { |klass| klass.metadata.serializations.keys }).uniq
        raise ::ArgumentError, "FieldStruct::Avro: no struct in #{@klass.name} declares serialize #{@serialization.inspect} " \
                               "(declared: #{declared.inspect})"
      end

      def parse(hash)
        ::Avro::Schema.parse(Oj.dump(hash, mode: :compat))
      rescue ::StandardError => e
        raise ::ArgumentError, "FieldStruct::Avro: #{@klass.name || @klass.inspect} doesn't make a valid Avro schema " \
                               "(check the avro: options of its fields and nested structs): #{e.message}"
      end
    end
  end
end
