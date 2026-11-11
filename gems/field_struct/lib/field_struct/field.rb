# frozen_string_literal: true

module FieldStruct
  # One declared attribute. Immutable once built.
  class Field
    # @return [Symbol]
    attr_reader :name
    # @return [Class] the type class (+Types::BigDecimal+ for +:decimal+)
    attr_reader :type
    # @return [FieldStruct::Types::Base] the instance the setter pipeline uses
    attr_reader :type_instance
    # @return [Object] the raw default: a literal, a callable, or nil for none
    attr_reader :default
    # @return [Symbol, nil] per-field coercion policy override
    attr_reader :coercion_policy
    # @return [String, nil]
    attr_reader :description
    # @return [String, nil] an RBS type that replaces the derived one
    attr_reader :rbs_type
    # @return [Hash{Symbol=>Object, nil}] frozen native and pass-through options
    attr_reader :options

    # @param name [Symbol, String]
    # @param type [Class] a +Types::Base+ subclass
    # @param type_instance [FieldStruct::Types::Base, nil] defaults to +type.new+
    # @param required [Boolean]
    # @param default [Object] a literal or a callable
    # @param coercion_policy [Symbol, nil]
    # @param description [String, nil]
    # @param rbs_type [String, nil]
    # @param sensitive [Boolean]
    # @param options [Object] native and pass-through options (keyword arguments)
    def initialize(name:, type:, type_instance: nil, required: false, default: nil, coercion_policy: nil,
                   description: nil, rbs_type: nil, sensitive: false, **options)
      @name = name.to_sym
      @setter_name = :"#{@name}="
      @ivar_name = :"@#{@name}"
      @type = type
      @type_instance = type_instance || type.new
      @required = required ? true : false
      @default = default
      @coercion_policy = coercion_policy
      @description = description
      @rbs_type = rbs_type
      @sensitive = sensitive ? true : false
      @options = options.freeze
      freeze
    end

    # Same as {#description}.
    #
    # @return [String, nil]
    def desc
      @description
    end

    # @return [Boolean]
    def required?
      @required
    end

    # @return [Boolean] whether +inspect+ masks this field's value
    def sensitive?
      @sensitive
    end

    # @return [String] +#<FieldStruct::Field :name Type flag... part...>+ (FS-B119)
    def inspect
      Describer.inspect_field(self)
    end

    # Prints {#inspect} on one line.
    #
    # @param printer [PP]
    # @return [void]
    def pretty_print(printer)
      printer.text(inspect)
    end

    # @return [Symbol] the writer method name
    def setter_name # rubocop:disable Style/TrivialAccessors
      @setter_name
    end

    # @return [Symbol] the instance variable holding the value
    def ivar_name # rubocop:disable Style/TrivialAccessors
      @ivar_name
    end
  end
end
