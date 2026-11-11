# frozen_string_literal: true

module FieldStruct
  # Ordered collection of a class's Fields, plus its per-format serialization mappings.
  class Metadata
    include Enumerable

    # One shared, frozen mapping for formats that were never declared.
    # @return [::Hash{::Symbol=>::String}]
    NO_MAPPING = {}.freeze
    NO_REVERSE = {}.freeze
    private_constant :NO_REVERSE

    def initialize
      @fields = {}
      @serializations = {}
      @reverse = {}
    end

    # @yieldparam field [FieldStruct::Field]
    # @return [Enumerator<FieldStruct::Field>, self]
    def each(&block)
      return enum_for(:each) unless block

      @fields.each_value(&block)
      self
    end

    # Adds a field; a field with the same name is replaced in place.
    #
    # @param field [FieldStruct::Field]
    # @return [self]
    def add(field)
      @fields[field.name] = field
      self
    end

    # @param name [Symbol, String]
    # @return [FieldStruct::Field, nil]
    def [](name)
      @fields[name.to_sym]
    end

    # @return [Array<Symbol>] a new Array each call
    def names
      @fields.keys
    end

    # @return [Hash{Symbol=>Hash{Symbol=>String}}] format name to its mapping
    attr_reader :serializations

    # Stores a mapping (frozen) for a format.
    #
    # @param name [Symbol, String] the format
    # @param mapping [Hash{Symbol=>String}] internal field name to external name
    # @return [self]
    def add_serialization(name, mapping)
      @serializations[name.to_sym] = mapping.frozen? ? mapping : mapping.dup.freeze
      self
    end

    # @param name [Symbol, String]
    # @return [Hash{Symbol=>String}] the frozen mapping, or a shared empty frozen Hash
    def serialization(name)
      @serializations.fetch(name.to_sym, NO_MAPPING)
    end

    # @param name [Symbol, String]
    # @return [Hash{String=>Symbol}] external name to internal name; empty if undeclared
    def reverse_serialization(name)
      mapping = serialization(name)
      return NO_REVERSE if mapping.empty?

      key = name.to_sym
      cached = @reverse[key]
      return cached.last if cached && cached.first.equal?(mapping)

      reverse = mapping.to_h { |internal, external| [external, internal] }.freeze
      @reverse[key] = [mapping, reverse] if mapping.frozen?
      reverse
    end

    # Adds every field and mapping of +parent+ that the receiver lacks. The receiver wins.
    #
    # @param parent [FieldStruct::Metadata]
    # @return [self]
    def merge(parent)
      parent.each { |field| @fields[field.name] = field unless @fields.key?(field.name) }
      parent.serializations.each { |format, mapping| @serializations[format] = mapping unless @serializations.key?(format) }
      self
    end

    # Without a block, the schema view (FS-B121): +{name => {type:, ruby_type:, required:, default:, options:, description:}}+
    # (plus +rbs_type+ and +sensitive+ when set), values made primitive. With a block it is +Enumerable#to_h+.
    #
    # @return [Hash{Symbol=>Hash{Symbol=>Object, nil}}]
    def to_h(&block)
      return super if block

      to_h { |field| [field.name, Describer.schema(field)] }
    end

    # One line per field: the field's name, a parenthesised label, and what it accepts (FS-B122).
    #
    # @return [String] +(no fields)+ when empty
    def describe
      return '(no fields)' if @fields.empty?

      map { |field| Describer.describe_field(field) }.join("\n")
    end

    # Fans out one field per line (FS-B120).
    #
    # @param printer [PP]
    # @return [void]
    def pretty_print(printer)
      return printer.text(inspect) if @fields.empty? && @serializations.empty?

      text = "#<#{FieldStruct.inspect_namespace}::Metadata"
      each { |field| text << "\n  #{field.inspect}" }
      text << "\n  serializations=#{@serializations.keys.inspect}" unless @serializations.empty?
      printer.text("#{text}\n>")
    end

    # @return [String]
    def inspect
      prefix = "#<#{FieldStruct.inspect_namespace}::Metadata"
      return "#{prefix} empty>" if @fields.empty? && @serializations.empty?

      suffix = @serializations.empty? ? '' : " serializations=#{@serializations.keys.inspect}"
      "#{prefix} fields=#{names.inspect}#{suffix}>"
    end
  end
end
