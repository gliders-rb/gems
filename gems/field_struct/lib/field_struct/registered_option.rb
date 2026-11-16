# frozen_string_literal: true

module FieldStruct
  # A field option an adapter or app registered with {FieldStruct.register_option}.
  class RegisteredOption
    # @return [Symbol] the option key, e.g. +:avro+
    attr_reader :name

    # @return [Array<Class>] the classes a declared value may be an instance of
    attr_reader :type

    # @return [String] the gem or app that reads the option
    attr_reader :owner

    # @param name [Symbol]
    # @param type [Array<Class>]
    # @param owner [String]
    def initialize(name, type, owner)
      @name = name
      @type = type.dup.freeze
      @owner = owner.dup.freeze
      freeze
    end
  end

  # Holds the registered field options and checks registrations (FS-B10a).
  # @api private
  module OptionRegistry
    # The keys the adapters in this repo register, so the error for one used before its adapter loads can say which
    # file to require. Nothing is loaded from here.
    # @return [::Hash{::Symbol=>::Array<::String>}] key to [gem name, require path]
    ADAPTER_KEYS = {
      avro: %w[field_struct-avro field_struct/avro],
      proto: %w[field_struct-protobuf field_struct/protobuf],
      json_schema: %w[field_struct-json_schema field_struct/json_schema]
    }.freeze

    @entries = {}.freeze

    class << self
      # @return [Hash{Symbol=>FieldStruct::RegisteredOption}] frozen, in registration order
      attr_reader :entries

      # @param name [Symbol]
      # @param type [Class, Array<Class>]
      # @param owner [String]
      # @return [Symbol] +name+
      # @raise [ArgumentError] for a bad argument, a universal or built-in native key, or a changed registration
      def register(name, type, owner)
        classes = check_arguments(name, type, owner)
        existing = @entries[name]
        return name if existing && existing.type == classes && existing.owner == owner

        refuse_existing(existing) if existing
        refuse_core(name)
        @entries = @entries.merge(name => RegisteredOption.new(name, classes, owner)).freeze
        name
      end

      # The message for a key nobody declares or registered.
      #
      # @param key [Symbol]
      # @param label [String] +Class#field+ or +field :name+
      # @param native [Array<Symbol>] the field type's own option keys
      # @return [String]
      def unknown_message(key, label, native)
        adapter = ADAPTER_KEYS[key]
        if adapter
          return "unknown option #{key}: on #{label}; #{key}: is registered by #{adapter[0]}, " \
                 "so require '#{adapter[1]}' before declaring the field"
        end

        candidates = native + FieldBuilder::UNIVERSAL_OPTIONS + @entries.keys + ADAPTER_KEYS.keys
        "unknown option #{key}: on #{label}#{Suggestion.clause(key, candidates, sigil: '', suffix: ':')}"
      end

      private

      def check_arguments(name, type, owner)
        unless name.is_a?(::Symbol)
          raise ::ArgumentError, "register_option takes the option name as a Symbol, got #{name.class} (#{name.inspect})"
        end

        classes = Array(type)
        if classes.empty? || !classes.all?(::Class)
          raise ::ArgumentError, "register_option type: must be a Class or an Array of Classes, got #{type.inspect}"
        end
        unless owner.is_a?(::String) && !owner.strip.empty?
          raise ::ArgumentError, "register_option owner: must name the gem or app that reads the option, got #{owner.inspect}"
        end

        classes
      end

      def refuse_existing(existing)
        raise ::ArgumentError, "#{existing.name}: is already registered by #{existing.owner} " \
                               "(type #{existing.type.map { |klass| OptionChecker.short(klass) }.join(' or ')}); " \
                               'register it again only with the same type: and owner:'
      end

      def refuse_core(name)
        if FieldBuilder::UNIVERSAL_OPTIONS.include?(name)
          raise ::ArgumentError, "#{name}: is a universal field option, so it can't be registered"
        end

        owners = FieldStruct.types.type_classes.select { |klass| klass.option_schema.key?(name) }
        return if owners.empty?

        raise ::ArgumentError, "#{name}: is a native option of #{owners.map(&:short_name).join(', ')}, so it can't be registered"
      end
    end
  end
end
