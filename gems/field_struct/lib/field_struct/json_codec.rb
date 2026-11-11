# frozen_string_literal: true

module FieldStruct
  # INTERNAL. The JSON side of {Base}: instance to JSON-ready Hash (+as_json+), and JSON text to instance (+from_json+).
  module JsonCodec
    FORMAT = :json

    class << self
      # @param record [FieldStruct::Base]
      # @return [Hash{Symbol=>Object}] Symbol keys (the +:json+ mapping applies), declaration order, every field
      def as_json(record)
        metadata = record.class.metadata
        mapping = metadata.serialization(FORMAT)
        result = {}
        metadata.each do |field|
          result[mapping.fetch(field.name, field.name).to_sym] = convert(record.public_send(field.name), renderer_for(field))
        end
        result
      end

      # @param klass [Class] a +FieldStruct::Base+ subclass
      # @param input [String, nil] JSON text
      # @return [FieldStruct::Base]
      # @raise [ArgumentError] for a non-object root
      # @raise [EncodingError] for malformed JSON
      def load(klass, input)
        parsed = parse(input)
        raise ArgumentError, "from_json expects a JSON object root, got #{parsed.class}" unless parsed.is_a?(::Hash)

        klass.new(canonical(klass, parsed))
      end

      private

      # --- dumping ---

      # The temporal type instance and format that render a field's values, or nil. Worked out once per Field.
      def renderer_for(field)
        cached = RENDERERS[field]
        return cached unless cached.nil?

        RENDERERS[field] = build_renderer(field) || NO_RENDERER
      end

      def build_renderer(field)
        type = field.type_instance
        return [type, field.options[:format]].freeze if type.is_a?(Types::Temporal)
        return nil unless type.is_a?(Types::Array)

        of_type = field.options[:of_type]
        element = of_type.is_a?(::Class) ? of_type.new : of_type
        element.is_a?(Types::Temporal) ? [element, field.options.dig(:element, :format)].freeze : nil
      end

      # nil, booleans, String, Integer and Float are the values JSON carries as they are.
      def convert(value, renderer)
        case value
        when ::NilClass, ::TrueClass, ::FalseClass, ::String, ::Integer, ::Float then value
        when ::Symbol then value.to_s
        when ::BigDecimal then value.to_s('F')
        when ::Date, ::Time then render_temporal(value, renderer)
        else convert_container(value, renderer)
        end
      end

      def convert_container(value, renderer)
        case value
        when ::Array then value.map { |item| convert(item, renderer) }
        when ::Hash then value.transform_values { |item| convert(item, renderer) }
        else convert_object(value)
        end
      end

      # A struct answers for itself; anything else is asked only if it can answer (the one allowlisted
      # +respond_to?+ on a framework-redefinable predicate, FS-B105: this arm is only reached for :value fields).
      def convert_object(value)
        return value.as_json if value.is_a?(Base)

        value.respond_to?(:as_json) ? value.as_json : value
      end

      def render_temporal(value, renderer)
        type, format = renderer.empty? ? DEFAULT_PAIR : renderer
        type.render(value, format: format)
      end

      # --- loading ---

      def parse(input)
        Oj.load(input, mode: :compat, decimal_class: ::BigDecimal)
      rescue ::EncodingError, Oj::ParseError => e
        raise ::EncodingError, sanitized_message(e.message), cause: nil
      end

      # Oj's text is "<description> (after <path>) at line L, column C [file:line] in '<input>'": keep description and position.
      def sanitized_message(message)
        description = message[/\A(.*?)(?: \(after |\z)/m, 1]
        position = message.match(/\) at line (\d+), column (\d+) \[/)
        "from_json could not parse its input as JSON (#{description}#{" at line #{position[1]}, column #{position[2]}" if position})"
      end

      # Rewrites a parsed object's keys to internal names, recursing where the field's type holds structs.
      def canonical(klass, hash)
        metadata = klass.metadata
        reverse = metadata.reverse_serialization(FORMAT)
        result = {}
        hash.each do |key, value|
          name = reverse.fetch(key.to_s) { key.to_s.to_sym }
          field = metadata[name]
          result[name] = field ? canonical_value(field, value) : value
        end
        result
      end

      def canonical_value(field, value)
        type = field.type_instance
        case type
        when Types::Nested then value.is_a?(::Hash) ? canonical(type.struct_class, value) : value
        when Types::Array then canonical_elements(field.options[:of_type], value)
        when Types::Union then value.is_a?(::Hash) ? canonical_union(type, value) : value
        else value
        end
      end

      def canonical_elements(of_type, value)
        return value unless of_type.is_a?(Types::Nested) && value.is_a?(::Array)

        value.map { |item| item.is_a?(::Hash) ? canonical(of_type.struct_class, item) : item }
      end

      # The first member that accepts the Hash wins: a struct member builds from the reverse-mapped Hash, any other
      # member leaves the Hash as it is. When none accepts, the raw Hash goes on to the field's policy.
      def canonical_union(union, hash)
        union.member_types.each do |member|
          return member.coerce(canonical(member.struct_class, hash)) if member.is_a?(Types::Nested)

          member.coerce(hash)
          return hash
        rescue *Types::Union::RESCUABLE
          next
        end
        hash
      end
    end

    DEFAULT_PAIR = [Types::Time.new, nil].freeze
    # Field => renderer pair (or NO_RENDERER); weak so dropped classes' Fields can be collected.
    RENDERERS = ObjectSpace::WeakMap.new
    NO_RENDERER = [].freeze
    private_constant :DEFAULT_PAIR, :RENDERERS, :NO_RENDERER
  end
end
