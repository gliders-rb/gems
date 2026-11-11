# frozen_string_literal: true

module FieldStruct
  # Subclass to declare typed fields. Every assignment coerces and validates that field only.
  #
  # @example
  #   class Book < FieldStruct::Base
  #     required :title, :string
  #     optional :pages, :integer
  #   end
  class Base
    # Names no field may take (they would shadow methods Base relies on); extended at the end of this class body.
    # @return [::Array<::Symbol>]
    EXPLICIT_RESERVED_NAMES = %i[
      errors attributes attribute_names assign_attributes as_json to_json to_h to_model model_name inspect hash class send
      public_send freeze instance_variable_set instance_variable_get initialize initialize_copy raise with dup clone eql?
      respond_to? valid? invalid? deconstruct deconstruct_keys
    ].freeze

    # Values +coercion_policy+ accepts.
    # @return [::Array<::Symbol>]
    VALID_COERCION_POLICIES = %i[keep_raw replace raise].freeze
    # Values +unknown_attributes+ accepts.
    # @return [::Array<::Symbol>]
    VALID_UNKNOWN_POLICIES = %i[ignore raise].freeze

    extend ClassMacros

    class << self
      # The class's declared fields and serialization mappings.
      #
      # @return [FieldStruct::Metadata]
      def metadata
        @metadata ||= Metadata.new
      end

      # Declares a field that is optional unless +required: true+ is passed.
      #
      # @param name [Symbol, String]
      # @param type [Symbol, String, Class] a registered name or a type class
      # @param options [Object] universal, native and pass-through options (keyword arguments)
      # @return [FieldStruct::Metadata]
      def field(name, type, **options)
        declare(name, type, options)
      end

      # Declares a required field (wins over a passed +required:+).
      #
      # @param (see .field)
      # @return [FieldStruct::Metadata]
      def required(name, type, **options)
        declare(name, type, options.merge(required: true))
      end

      # Declares an optional field (wins over a passed +required:+).
      #
      # @param (see .field)
      # @return [FieldStruct::Metadata]
      def optional(name, type, **options)
        declare(name, type, options.merge(required: false))
      end

      # @return [Array<Symbol>] the field names in declaration order; a new Array each call
      def attribute_names
        metadata.names
      end

      # Looks a type name up through the class's namespace registry chain.
      #
      # @param name [Symbol, String]
      # @return [Class]
      # @raise [KeyError] when no registry knows the name
      def resolve_type(name)
        namespace_registry.lookup(name)
      end

      # The registry of the nearest enclosing module that exposes +field_types+, else the base registry.
      # @return [FieldStruct::Registry] the chain this class resolves type names through (semi-internal)
      def namespace_registry
        return FieldStruct.types unless name

        segments = name.split('::')[0...-1]
        until segments.empty?
          container = constant_at(segments)
          return container.field_types if container.respond_to?(:field_types)

          segments.pop
        end
        FieldStruct.types
      end

      # The class name, then one line per field with its type, options and what the type accepts.
      #
      # @return [String]
      def describe
        "#{display_name}\n#{metadata.describe}"
      end

      # @return [FieldStruct::ModelName] memoized per class
      def model_name
        @model_name ||= ModelName.new(display_name)
      end

      # @return [String] the class name, or +AnonymousFieldStruct+
      def display_name
        name || 'AnonymousFieldStruct'
      end

      private

      def declare(name, type, options)
        field = FieldBuilder.call(self, name, type, options)
        metadata.add(field)
        define_accessors(field)
        metadata
      end

      def define_accessors(field)
        ivar = field.ivar_name
        generated_methods.define_method(field.name) { instance_variable_get(ivar) }
        generated_methods.define_method(field.setter_name) { |value| fs_write(field, value) }
      end

      def generated_methods
        @generated_methods ||= Module.new.tap { |mod| include(mod) }
      end

      def constant_at(segments)
        Object.const_get(segments.join('::'))
      rescue NameError
        nil
      end
    end

    # @param attrs [Hash{Symbol,String=>Object, nil}, #to_hash, nil] attribute values; Symbol or String keys
    # @raise [ArgumentError] when +attrs+ is not Hash-like
    def initialize(attrs = {})
      input = fs_hash_input(attrs.nil? ? {} : attrs, 'new')
      @__errors__ = Errors.new
      fs_check_unknown(input)
      fs_apply_defaults(input)
      fs_assign(input)
      fs_run_validators
      @__ready__ = true
      freeze if self.class.frozen_on_construct?
    end

    # Runs the setter of every known key; unmentioned fields are untouched.
    #
    # @param attrs [Hash{Symbol,String=>Object, nil}, #to_hash]
    # @return [self]
    # @raise [ArgumentError] when +attrs+ is not Hash-like
    def assign_attributes(attrs)
      input = fs_hash_input(attrs, 'assign_attributes')
      fs_check_unknown(input)
      fs_assign(input)
      self
    end

    # A copy with some fields changed; the receiver is untouched. Works on immutable and frozen instances.
    #
    # @param positional [::Array<::Object>] refused; present only to give a clear error
    # @param changes [Hash{Symbol,String=>Object}] new values, run through the full setter pipeline
    # @return [FieldStruct::Base] a new instance of the receiver's class
    # @raise [ArgumentError] when given positional arguments
    def with(*positional, **changes)
      unless positional.empty?
        raise ArgumentError, "#{self.class.display_name}#with takes keyword arguments only, " \
                             "got #{positional.size} positional; pass a Hash as with(**hash)"
      end

      copy = dup
      copy.send(:fs_amend, changes, frozen?)
    end

    # @return [Hash{Symbol=>Object, nil}] canonical names in declaration order; a fresh Hash
    def attributes
      self.class.metadata.to_h { |field| [field.name, public_send(field.name)] }
    end

    # Same as {#attributes}.
    #
    # @return [Hash{Symbol=>Object, nil}]
    def to_h
      attributes
    end

    # @return [Array<Symbol>]
    def attribute_names
      self.class.attribute_names
    end

    # @return [FieldStruct::Errors]
    def errors
      @__errors__
    end

    # Re-runs the cross-field validators (if the class has any), then reads the errors.
    #
    # @return [Boolean] whether no field has an error
    def valid?
      fs_run_validators
      errors.empty?
    end

    # @return [Boolean]
    def invalid?
      !valid?
    end

    # @param other [Object]
    # @return [Boolean] same class exactly and equal attributes
    def ==(other)
      other.instance_of?(self.class) && attributes == other.attributes
    end

    # Same as {#==}.
    #
    # @param other [Object]
    # @return [Boolean]
    def eql?(other)
      self == other
    end

    # @return [Integer]
    def hash
      [self.class, attributes].hash
    end

    # The attributes as JSON-ready values: Symbol keys named by the +:json+ mapping, every field present.
    #
    # @param _options [Object] ignored
    # @return [Hash{Symbol=>Object, nil}]
    def as_json(_options = nil)
      JsonCodec.as_json(self)
    end

    # @param _options [Object] ignored
    # @return [String] +Oj.dump(as_json, mode: :compat)+
    def to_json(_options = nil)
      Oj.dump(as_json, mode: :compat)
    end

    # Pattern matching on canonical field names.
    #
    # @param keys [Array<Symbol>, nil] +nil+ asks for everything
    # @return [Hash{Symbol=>Object, nil}]
    def deconstruct_keys(keys)
      keys.nil? ? attributes : attributes.slice(*keys)
    end

    # @return [Array<Object, nil>] field values in declaration order
    def deconstruct
      attributes.values
    end

    # @return [FieldStruct::ModelName]
    def model_name
      self.class.model_name
    end

    # @return [self]
    def to_model
      self
    end

    # @return [String] +#<Name field: value, ...>+ with an +errors:+ suffix when invalid
    def inspect
      Describer.inspect_instance(self)
    end

    # Prints {#inspect} (sensitive values masked) on one line.
    #
    # @param printer [PP]
    # @return [void]
    def pretty_print(printer)
      printer.text(inspect)
    end

    private

    def initialize_copy(source)
      super
      @__errors__ = source.errors.dup
    end

    # Runs on the copy made by +with+: lets setters through even on an immutable class, then restores state.
    def fs_amend(changes, freeze_after)
      @__ready__ = false
      assign_attributes(changes)
      fs_run_validators
      @__ready__ = true
      freeze if freeze_after
      self
    end

    def fs_check_unknown(input)
      return unless self.class.unknown_attributes == :raise

      unknown = input.keys.reject { |key| fs_known_field(key) }.map { |key| key.to_s.to_sym }
      return if unknown.empty?

      raise UnknownAttributeError.new("unknown attribute(s) for #{self.class.inspect}: #{unknown.map(&:inspect).join(', ')}",
                                      keys: unknown)
    end

    def fs_run_validators
      validators = self.class.validators
      return if validators.empty?

      errors.clear(:base)
      validators.each { |validator| validator.call(self) }
    end

    def fs_hash_input(attrs, caller_name)
      return attrs.to_hash if attrs.respond_to?(:to_hash)

      owner = self.class.display_name
      separator = caller_name == 'new' ? '.' : '#'
      raise ArgumentError,
            "#{owner}#{separator}#{caller_name} expects a Hash (or an object responding to #to_hash), got #{attrs.class}"
    end

    def fs_known_field(key)
      return nil unless key.is_a?(::Symbol) || key.is_a?(::String)

      self.class.metadata[key]
    end

    def fs_apply_defaults(input)
      self.class.metadata.each do |field|
        if field.default.nil? && (input.key?(field.name) || input.key?(field.name.name))
          instance_variable_set(field.ivar_name, nil)
        else
          public_send(field.setter_name, fs_default_value(field))
        end
      end
    end

    def fs_default_value(field)
      field.default.respond_to?(:call) ? field.default.call : field.default
    end

    def fs_assign(input)
      input.each do |key, value|
        field = fs_known_field(key)
        public_send(field.setter_name, value) if field
      end
    end

    # The setter pipeline: coerce, store, validate this field.
    def fs_write(field, value)
      raise ImmutableError, "#{self.class.inspect} is immutable; cannot reassign #{field.name}" if @__ready__ && self.class.immutable?

      failure = nil
      coerced = begin
        field.type_instance.coerce(value, **field.options)
      rescue Types::Nested::Rejection => e
        raise e.original
      rescue ::ArgumentError, ::TypeError, ::RangeError => e
        failure = e
      end
      return fs_coercion_failed(field, value, failure) if failure

      instance_variable_set(field.ivar_name, coerced)
      fs_validate(field, coerced)
      coerced
    end

    def fs_coercion_failed(field, value, failure)
      policy = field.coercion_policy || self.class.coercion_policy
      if policy == :raise
        raise CoercionError.new("could not coerce #{value.class} input for #{field.name}: #{failure.message}",
                                field_name: field.name, original: failure), cause: failure
      end

      instance_variable_set(field.ivar_name, policy == :replace ? nil : value)
      errors.clear(field.name)
      errors.add(field.name, "could not be coerced: #{failure.message}")
      policy == :replace ? nil : value
    end

    def fs_validate(field, value)
      errors.clear(field.name)
      if field.type_instance.missing?(value)
        errors.add(field.name, 'is required') if field.required?
      elsif Restrictions.violated?(value, field.options) || fs_invalid_struct?(value)
        errors.add(field.name, 'is invalid')
      else
        fs_validate_elements(field, value)
      end
    end

    # A nested struct, or an Array holding at least one, that is itself invalid.
    def fs_invalid_struct?(value)
      return value.invalid? if value.is_a?(Base)

      value.is_a?(::Array) && value.any? { |item| item.is_a?(Base) && item.invalid? }
    end

    def fs_validate_elements(field, value)
      element = field.options[:element]
      return unless element && value.is_a?(::Array)

      bad = value.each_index.select { |index| Restrictions.violated?(value[index], element) }
      errors.add(field.name, Types::Array.invalid_elements_message(bad)) unless bad.empty?
    end
  end

  class Base
    # Names no field may take: the documented list plus this class's own private helpers.
    # @return [::Array<::Symbol>]
    RESERVED_FIELD_NAMES = (EXPLICIT_RESERVED_NAMES + private_instance_methods(false).grep(/\Afs_/)).freeze
  end
end
