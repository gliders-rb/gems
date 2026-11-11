# frozen_string_literal: true

module FieldStruct
  # INTERNAL: renders fields for +Field#inspect+, +Metadata#to_h+ and +Metadata#describe+ (FS-B119, FS-B121, FS-B122).
  module Describer
    SEPARATOR = ' — '

    module_function

    # @param field [FieldStruct::Field]
    # @return [String] +#<FieldStruct::Field :name Type flag... part...>+
    def inspect_field(field)
      parts = [field.name.inspect, type_label(field.type_instance)] + flags(field) + settings(field)
      parts.concat(field.options.map { |key, value| "#{key}=#{repr(value)}" })
      "#<#{FieldStruct.inspect_namespace}::Field #{parts.join(' ')}>"
    end

    def flags(field)
      [('required' if field.required?), ('sensitive' if field.sensitive?)].compact
    end

    def settings(field)
      [
        (field.default.nil? ? nil : "default=#{field.default.inspect}"),
        field.coercion_policy && "coercion_policy=#{field.coercion_policy.inspect}",
        field.description && "description=#{field.description.inspect}",
        field.rbs_type && "rbs_type=#{field.rbs_type.inspect}"
      ].compact
    end

    # An instance's +inspect+: sensitive values masked, errors appended (FS-B115, FS-B139).
    def inspect_instance(instance)
      pairs = instance.class.metadata.map { |field| "#{field.name}: #{masked(instance, field)}" }
      "#<#{instance.class.display_name} #{pairs.join(', ')}#{errors_suffix(instance.errors)}>"
    end

    def masked(instance, field)
      value = instance.public_send(field.name)
      field.sensitive? && !value.nil? ? FieldStruct::FILTERED : value.inspect
    end

    def errors_suffix(errors)
      return '' if errors.empty?

      " errors: {#{errors.to_h.map { |field, messages| "#{field}: #{messages.inspect}" }.join(', ')}}"
    end

    # @param type [FieldStruct::Types::Base] a type instance
    # @return [String] +String+, +Nested(Address)+ or +Union(String | Integer)+
    def type_label(type)
      case type
      when Types::Nested then "Nested(#{struct_name(type.struct_class)})"
      when Types::Union then "Union(#{type.member_types.map { |member| type_label(member) }.join(' | ')})"
      else type.class.short_name
      end
    end

    # The short name of a struct class, or +AnonymousFieldStruct+.
    def struct_name(klass)
      klass.name ? klass.name.split('::').last : 'AnonymousFieldStruct'
    end

    # Renders an option value for +inspect+ and +describe+.
    def repr(value)
      case value
      when ::Class then class_name(value)
      when Types::Base then type_label(value)
      when ::Hash then "{#{value.map { |key, item| "#{hash_key(key)}#{repr(item)}" }.join(', ')}}"
      when ::Array then "[#{value.map { |item| repr(item) }.join(', ')}]"
      else value.inspect
      end
    end

    def class_name(klass)
      klass.name ? klass.name.split('::').last : 'AnonymousType'
    end

    def hash_key(key)
      key.is_a?(::Symbol) && key.inspect == ":#{key}" ? "#{key}: " : "#{key.inspect} => "
    end

    # The schema view of one field (FS-B121).
    def schema(field)
      type = field.type_instance
      entry = {
        type: field.type.short_name,
        ruby_type: [type.ruby_type].flatten.map { |klass| klass.name || klass.inspect }.join(' | '),
        required: field.required?,
        default: primitive(field.default),
        options: primitive(field.options),
        description: field.description
      }
      entry[:rbs_type] = field.rbs_type if field.rbs_type
      entry[:sensitive] = true if field.sensitive?
      entry
    end

    def callable?(value)
      value.respond_to?(:call)
    end

    # Makes a value primitive for +Metadata#to_h+.
    def primitive(value)
      case value
      when ::Class then class_name(value)
      when Types::Base then value.class.short_name
      when ::Hash, ::Array then primitive_container(value)
      else callable?(value) ? '<callable>' : value
      end
    end

    def primitive_container(value)
      value.is_a?(::Hash) ? value.to_h { |key, item| [key, primitive(item)] } : value.map { |item| primitive(item) }
    end

    # One +describe+ line (FS-B122).
    def describe_field(field)
      head = [label(field), field.required? ? 'required' : 'optional', ('sensitive' if field.sensitive?)].compact
      segments = ["  #{field.name} (#{head.join(', ')})", field.description&.inspect, declared_text(field),
                  accepts_segment(field), element_segment(field)]
      segments.compact.join(SEPARATOR)
    end

    def declared_text(field)
      declared = field.options.compact
      declared.map { |key, value| "#{key}: #{repr(value)}" }.join(', ') unless declared.empty?
    end

    def accepts_segment(field)
      text = accepts_text(field.type)
      "accepts #{text}" unless text.empty?
    end

    def element_segment(field)
      names = element_names(field)
      "element accepts #{names.join(', ')}" if field.type_instance.is_a?(Types::Array) && !names.empty?
    end

    def label(field)
      type = field.type_instance
      return field.type.short_name unless type.is_a?(Types::Nested) && type.struct_class.name

      struct_name(type.struct_class)
    end

    def accepts_text(type_class)
      type_class.option_schema.map do |name, descriptor|
        shapes = descriptor[:type].map { |klass| klass.name.split('::').last }.join(' | ')
        shapes += "; presets: #{descriptor[:presets].join(', ')}" unless descriptor[:presets].empty?
        "#{name}#{'*' if descriptor[:required]} (#{shapes})"
      end.join(', ')
    end

    def element_names(field)
      of_type = field.options[:of_type]
      return [] unless of_type

      Types::Array.element_class(of_type).option_schema.keys.map(&:to_s)
    end
  end
end
