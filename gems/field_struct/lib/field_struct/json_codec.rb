# frozen_string_literal: true

module FieldStruct
  # INTERNAL. The JSON side of {Base}: instance to JSON-ready Hash (+as_json+), and JSON text to instance (+from_json+).
  module JsonCodec
    FORMAT = :json

    class << self
      # Inside {.dump}, BigDecimals stay raw JSON numbers (FS-B106a); anywhere else they are Strings.
      #
      # @param record [FieldStruct::Base]
      # @return [Hash{Symbol=>Object}] Symbol keys (the +:json+ mapping applies), declaration order, every field
      #   unless the class's +json_omit+ leaves some out
      def as_json(record)
        numbers = Thread.current[NUMBERS] == true
        klass = record.class
        metadata = klass.metadata
        mapping = metadata.serialization(FORMAT)
        given = klass.json_omit == :unset ? record.given_fields : nil
        result = {}
        metadata.each do |field|
          value = record.public_send(field.name)
          next if given && value.nil? && !given.include?(field.name)

          result[mapping.fetch(field.name, field.name).to_sym] = convert(value, renderer_for(field), numbers?(numbers, field))
        end
        result
      end

      # +Oj.dump(record.as_json)+ with decimals as exact numbers, unless a field or its type keeps the string (FS-B106a).
      # It goes through +as_json+, so a subclass's override (and +super+ inside it) is honoured. The flag is
      # fiber-local, so another fiber's +as_json+ is not affected.
      #
      # @param record [FieldStruct::Base]
      # @return [String] JSON text
      def dump(record)
        outer = Thread.current[NUMBERS]
        Thread.current[NUMBERS] = true
        Oj.dump(record.as_json, mode: :compat)
      ensure
        Thread.current[NUMBERS] = outer
      end

      # Runs the block with foreign objects written as descriptions (FS-B105a); fiber-local, restored after.
      #
      # @return [Object] the block's result
      def describing
        outer = Thread.current[DESCRIBE]
        Thread.current[DESCRIBE] = true
        yield
      ensure
        Thread.current[DESCRIBE] = outer
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
        return nil unless type.is_a?(Types::Array) || type.is_a?(Types::Hash)

        of_type = field.options[:of_type]
        element = of_type.is_a?(::Class) ? of_type.new : of_type
        element.is_a?(Types::Temporal) ? [element, field.options.dig(:element, :format)].freeze : nil
      end

      # Inside {.dump}, whether this field's decimals go out as numbers.
      def numbers?(numbers, field)
        numbers && !decimal_string?(field)
      end

      # Whether a decimal field (or an array or map of decimals) writes Strings in +to_json+: its +json:+, else its
      # type's default.
      def decimal_string?(field)
        type = field.type_instance
        return field.options.fetch(:json) { type.class.json_default } == :string if type.is_a?(Types::BigDecimal)

        (type.is_a?(Types::Array) || type.is_a?(Types::Hash)) && element_decimal_string?(field)
      end

      def element_decimal_string?(field)
        of_type = field.options[:of_type]
        klass = of_type.is_a?(::Class) ? of_type : of_type.class
        return false unless klass <= Types::BigDecimal

        (field.options.dig(:element, :json) || klass.json_default) == :string
      end

      # nil, booleans, String, Integer and Float are the values JSON carries as they are.
      def convert(value, renderer, numbers)
        case value
        when ::NilClass, ::TrueClass, ::FalseClass, ::String, ::Integer, ::Float then value
        when ::Symbol then value.to_s
        when ::BigDecimal then numbers ? RawNumber.new(value) : value.to_s('F')
        when ::Date, ::Time then render_temporal(value, renderer)
        else convert_container(value, renderer, numbers)
        end
      end

      def convert_container(value, renderer, numbers)
        case value
        when ::Array then value.map { |item| convert(item, renderer, numbers) }
        when ::Hash then value.transform_values { |item| convert(item, renderer, numbers) }
        else convert_object(value)
        end
      end

      # A struct answers for itself; anything else is asked only if it can answer (the one allowlisted
      # +respond_to?+ on a framework-redefinable predicate, FS-B105: this arm is only reached for :value fields).
      def convert_object(value)
        return value.as_json if value.is_a?(Base)
        return describe(value) if Thread.current[DESCRIBE] && !value.is_a?(::Numeric)

        value.respond_to?(:as_json) ? value.as_json : value
      end

      # "#<Lantern id=4>": reads the class and, when there is one, the id; nothing else is called.
      def describe(value)
        name = value.class.name || 'anonymous'
        value.respond_to?(:id) ? "#<#{name} id=#{value.id}>" : "#<#{name}>"
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
        when Types::Hash then canonical_entries(field.options[:of_type], value)
        when Types::Union then value.is_a?(::Hash) ? canonical_union(type, value) : value
        else value
        end
      end

      def canonical_elements(of_type, value)
        return value unless of_type.is_a?(Types::Nested) && value.is_a?(::Array)

        value.map { |item| item.is_a?(::Hash) ? canonical(of_type.struct_class, item) : item }
      end

      def canonical_entries(of_type, value)
        return value unless of_type.is_a?(Types::Nested) && value.is_a?(::Hash)

        value.transform_values { |item| item.is_a?(::Hash) ? canonical(of_type.struct_class, item) : item }
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
    # The fiber-local key {.describing} sets (FS-B105a).
    DESCRIBE = :__field_struct_describe_foreign__
    # The fiber-local key {.dump} sets while +as_json+ runs.
    NUMBERS = :__field_struct_json_numbers__

    # A BigDecimal in the +to_json+ tree: Oj's compat mode embeds what +to_json+ returns, so the exact digits go out
    # as a JSON number (FS-B106a; measured with Oj 3.17.8, with and without the json library loaded).
    class RawNumber
      # @param decimal [BigDecimal]
      def initialize(decimal)
        @text = decimal.to_s('F')
      end

      # @return [String] the plain digits
      def to_json(*)
        @text
      end
    end
    private_constant :DEFAULT_PAIR, :RENDERERS, :NO_RENDERER, :DESCRIBE, :NUMBERS, :RawNumber
  end
end
