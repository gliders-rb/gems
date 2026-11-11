# frozen_string_literal: true

module FieldStruct
  # Starter source for FieldStruct classes, guessed from JSON examples. A prototype to refine: risky guesses are
  # reported as trailing comments instead of being committed to.
  module Scaffold
    # Ruby keywords; a JSON key that sanitizes to one gets a +_field+ suffix.
    # @return [::Array<::String>]
    KEYWORDS = %w[
      alias and begin BEGIN break case class def defined? do else elsif end END ensure false for if in module next nil
      not or redo rescue retry return self super then true undef unless until when while yield __FILE__ __LINE__ __ENCODING__
    ].freeze

    # Core class names a generated class must not reopen.
    # @return [::Array<::String>]
    CORE_NAMES = %w[
      Array BigDecimal Class Comparable Data Date DateTime Dir File Float Hash Integer IO Kernel Method Module Numeric
      Object Proc Range Regexp Set String Struct Symbol Time
    ].freeze

    # Matches a numeric-looking string.
    # @return [::Regexp]
    NUMERIC = /\A-?\d+(?:\.\d+)?\z/
    # Most distinct values an enum-like String field can have.
    # @return [::Integer]
    ENUM_MAX_DISTINCT = 6
    # Fewest values a String field needs before it is called enum-like.
    # @return [::Integer]
    ENUM_MIN_VALUES = 3

    class << self
      # Builds starter source for one class (plus helper classes) from one example or an array of same-shape examples.
      #
      # @param input [String, Hash{String=>Object, nil}, Array<Hash{String=>Object, nil}>] a JSON String, or already-parsed data
      # @param class_name [String] the name of the top class
      # @return [String] Ruby source ending with a newline
      # @raise [ArgumentError] for input that is not an object or an array of objects, or an empty array
      def from_json(input, class_name: 'Generated')
        parsed = input.is_a?(::String) ? Oj.load(input, mode: :strict) : input
        samples = samples_from(parsed)
        generator = Generator.new(class_name)
        generator.build(class_name, samples)
        generator.sources.join("\n")
      end

      private

      def samples_from(parsed)
        samples = case parsed
                  when ::Hash then [parsed]
                  when ::Array then parsed
                  else raise ::ArgumentError, "expected a JSON object or array of objects, got #{parsed.class}"
                  end
        raise ::ArgumentError, 'no samples to scaffold from' if samples.empty?
        raise ::ArgumentError, 'every sample must be a JSON object' unless samples.all?(::Hash)

        samples.map { |sample| sample.transform_keys(&:to_s) }
      end
    end

    # INTERNAL: walks the samples and emits one class source per object shape.
    class Generator
      # @return [Array<String>] class sources, children before parents, each ending with a newline
      attr_reader :sources

      # @param top_name [::String] the top-level class name, kept free of collisions
      def initialize(top_name)
        @taken = CORE_NAMES + [top_name]
        @sources = []
      end

      # @param name [String] the class name
      # @param samples [::Array<::Hash{::String=>::Object}>] String-keyed objects
      # @return [::Array<::String>] the sources so far
      def build(name, samples)
        names = Names.new
        lines = []
        mapping = {}
        keys_of(samples).each do |key|
          field_name = names.field_name(key)
          mapping[field_name] = key unless field_name == key
          lines << field_line(field_name, key, samples)
        end
        @sources << render(name, lines, mapping)
      end

      private

      def keys_of(samples)
        samples.flat_map(&:keys).uniq
      end

      def render(name, lines, mapping)
        body = lines.empty? ? ['  # (no fields detected in samples)'] : lines
        body += ['', "  serialize :json, #{mapping.map { |field, key| "#{field}: #{key.inspect}" }.join(', ')}"] unless mapping.empty?
        "class #{name} < FieldStruct::Base\n#{body.join("\n")}\nend\n"
      end

      def field_line(field_name, key, samples)
        stat = Stat.new(key, samples)
        type, notes = type_for(stat, key)
        parts = (stat.availability + notes).compact
        line = "  #{stat.required? ? 'required' : 'optional'} :#{field_name}, #{type}"
        parts.empty? ? line : "#{line} # #{parts.join('; ')}"
      end

      # @return [Array(String, Array<String>)] the type expression and the hint parts
      def type_for(stat, key)
        kinds = stat.kinds
        return [':string', [stat.always_null_hint]] if kinds.empty?
        return [':value', ["mixed types in samples (#{kinds.join(', ')}) — review"]] if stat.mixed?

        case stat.kind
        when :object then [build_child(key, stat.values), []]
        when :array then array_type(stat, key)
        else [":#{stat.kind}", stat.string_hints]
        end
      end

      def array_type(stat, key)
        elements = stat.values.flatten(1)
        return [':array, of: :value', ['empty array(s) in samples — element type unknown']] if elements.empty?

        [":array, of: #{element_type(elements, key)}", []]
      end

      def element_type(elements, key)
        stat = Stat.of_values(elements)
        return ':string' if stat.kinds.empty?
        return ':value' if stat.mixed?

        case stat.kind
        when :object then build_child(singular(key), stat.values)
        when :array then ':value'
        else ":#{stat.kind}"
        end
      end

      def build_child(key, samples)
        name = class_name_for(key)
        build(name, samples.map { |sample| sample.transform_keys(&:to_s) })
        name
      end

      def singular(key)
        key.length > 1 && key.end_with?('s') ? key[0...-1] : key
      end

      def class_name_for(key)
        base = Names.words(key).map { |word| word[0].upcase + word[1..] }.join
        base = "N#{base}" unless base.match?(/\A[A-Z]/)
        name = base
        counter = 2
        while @taken.include?(name)
          name = "#{base}#{counter}"
          counter += 1
        end
        @taken << name
        name
      end
    end

    # INTERNAL: what the samples say about one key.
    class Stat
      # @return [Array<Object>] the non-null values, in sample order
      attr_reader :values

      # @param values [::Array<::Object>] non-null sample values
      # @return [FieldStruct::Scaffold::Stat]
      def self.of_values(values)
        new(nil, [], values)
      end

      # @param key [::String, nil] the key to read from each sample
      # @param samples [::Array<::Hash{::String=>::Object}>] String-keyed objects
      # @param values [::Array<::Object>, nil] values to use instead of reading the samples
      def initialize(key, samples, values = nil)
        @total = samples.size
        @present = key ? samples.count { |sample| sample.key?(key) } : 0
        all = values || samples.filter_map { |sample| [sample[key]] if sample.key?(key) }.flatten(1)
        @all = all
        @values = all.compact
      end

      def required?
        @present == @total && @all.none? { |value| blank?(value) }
      end

      # The distinct non-null kinds, in order of first appearance.
      #
      # @return [::Array<::Symbol>]
      def kinds
        @kinds ||= @values.map { |value| kind_of(value) }.uniq
      end

      def mixed?
        kind.nil?
      end

      # The single kind the values agree on (integers and floats merge to float), or nil when they disagree.
      #
      # @return [::Symbol, nil]
      def kind
        return (kinds.size == 1 ? kinds.first : nil) unless (kinds - %i[integer float]).empty? && kinds.size == 2

        :float
      end

      # @return [::Array<::String>] hint parts about missing or empty values
      def availability
        blanks = @all.count { |value| blank?(value) }
        if @present < @total then ["present #{@present}/#{@total}"]
        elsif blanks.positive? && blanks < @total then ["empty/null in #{blanks}/#{@total}"]
        else []
        end
      end

      # @return [::String]
      def always_null_hint
        'always null/absent in samples — type unknown'
      end

      # Hints for a String field: numeric-looking, enum-like, or always blank.
      #
      # @return [::Array<::String>]
      def string_hints
        return [] unless kind == :string

        filled = @values.reject { |value| blank?(value) }
        return ['always empty in samples — type unknown'] if filled.empty?
        return [numeric_hint(filled)] if filled.all? { |value| value.match?(NUMERIC) }

        enum_hint(filled)
      end

      private

      def numeric_hint(filled)
        guess = filled.any? { |value| value.include?('.') } ? ':big_decimal?' : ':integer?'
        "numeric-looking (e.g. #{filled.first.inspect}) — #{guess} or keep :string if an id/code"
      end

      def enum_hint(filled)
        distinct = filled.uniq
        return [] unless filled.size >= ENUM_MIN_VALUES && distinct.size < filled.size && distinct.size <= ENUM_MAX_DISTINCT

        ["values: #{distinct.inspect} — enum?"]
      end

      def blank?(value)
        value.nil? || (value.is_a?(::String) && value.strip.empty?) || (value.is_a?(::Array) && value.empty?)
      end

      def kind_of(value)
        case value
        when true, false then :boolean
        when ::Integer then :integer
        when ::Numeric then :float
        when ::String then :string
        when ::Hash then :object
        else :array
        end
      end
    end

    # INTERNAL: turns JSON keys into distinct, legal field names (FS-B136).
    class Names
      # @param key [String]
      # @return [Array<String>] lowercase words of the key
      def self.words(key)
        spaced = key.gsub(/(?<=[A-Z])(?=[A-Z][a-z])/, ' ').gsub(/(?<=[a-z\d])(?=[A-Z])/, ' ')
        spaced.split(/[^A-Za-z0-9]+/).reject(&:empty?)
      end

      def initialize
        @used = []
      end

      # @param key [String] the JSON key
      # @return [String] a field name no earlier key received
      def field_name(key)
        base = self.class.words(key).join('_').downcase
        base = "field_#{base}" if base.empty? || base.match?(/\A\d/)
        base = "#{base}_field" if KEYWORDS.include?(base) || FieldStruct::Base::RESERVED_FIELD_NAMES.include?(base.to_sym)
        name = base
        counter = 2
        while @used.include?(name)
          name = "#{base}#{counter}"
          counter += 1
        end
        @used << name
        name
      end
    end
  end
end
