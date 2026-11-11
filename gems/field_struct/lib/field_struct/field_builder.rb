# frozen_string_literal: true

module FieldStruct
  # Turns the arguments of +field+ / +required+ / +optional+ into a {Field}.
  module FieldBuilder
    # Options valid on any field; they become Field attributes and are not passed to +coerce+.
    UNIVERSAL_OPTIONS = %i[required default coercion_policy description desc rbs_type sensitive].freeze

    # @param owner [Class] the +Base+ subclass doing the declaring
    # @param name [Symbol, String]
    # @param type [Symbol, String, Class]
    # @param options [Hash{Symbol=>Object}]
    # @return [FieldStruct::Field]
    # @raise [ArgumentError, KeyError] for a misdeclared field
    def self.call(owner, name, type, options)
      name = name.to_sym
      reject_reserved(name)
      universal = options.slice(*UNIVERSAL_OPTIONS)
      check_universal(universal)
      registry = owner.namespace_registry
      type_class, nested = resolve_type(owner, type)
      resolved = OptionChecker.call(type_class, options.except(*UNIVERSAL_OPTIONS), registry: registry, field_name: name)
      instance, stored = nested ? [nested, resolved] : type_class.instantiate(resolved)
      Field.new(name: name, type: type_class, type_instance: instance, required: universal[:required], default: universal[:default],
                coercion_policy: universal[:coercion_policy], description: description_from(universal),
                rbs_type: universal[:rbs_type], sensitive: universal[:sensitive], **stored)
    end

    def self.reject_reserved(name)
      return unless Base::RESERVED_FIELD_NAMES.include?(name)

      raise ArgumentError,
            "field #{name.inspect} is reserved: FieldStruct::Base relies on ##{name}, and a field would shadow it. " \
            "Pick another name; serialize :json can keep the external key (e.g. serialize :json, #{name}_field: '#{name}')."
    end

    # Step 2 of the declaration order: description/desc, coercion_policy, rbs_type, sensitive.
    def self.check_universal(universal)
      description_from(universal)
      check_policy(universal[:coercion_policy])
      check_rbs_type(universal[:rbs_type]) if universal.key?(:rbs_type)
      check_sensitive(universal[:sensitive]) if universal.key?(:sensitive)
    end

    def self.check_policy(policy)
      return if policy.nil? || Base::VALID_COERCION_POLICIES.include?(policy)

      raise ArgumentError, "unknown coercion policy #{policy.inspect} (expected one of #{Base::VALID_COERCION_POLICIES.inspect})"
    end

    def self.check_rbs_type(value)
      return if value.nil? || (value.is_a?(::String) && !value.strip.empty?)

      raise ArgumentError, "rbs_type: must be a non-empty String of RBS (e.g. rbs_type: '::ActiveRecord::Relation'), got #{value.inspect}"
    end

    def self.check_sensitive(value)
      return if [true, false].include?(value)

      raise ArgumentError, "sensitive: must be true or false, got #{value.class}"
    end

    def self.description_from(universal)
      raise ArgumentError, 'pass either description: or desc:, not both' if universal.key?(:description) && universal.key?(:desc)

      universal[:description] || universal[:desc]
    end

    # @return [Array(Class, FieldStruct::Types::Nested)] the type class and, for a nested struct, its instance
    def self.resolve_type(owner, type)
      klass = type.is_a?(::Class) ? type : owner.resolve_type(type)
      return [Types::Nested, Types::Nested.new(klass)] if nested?(klass)
      unless klass.is_a?(::Class) && klass <= Types::Base
        raise ArgumentError, "#{klass.inspect} is not a FieldStruct type (subclass FieldStruct::Types::Base)"
      end

      [klass, nil]
    end

    def self.nested?(klass)
      klass.is_a?(::Class) && klass < Base
    end

    private_class_method :reject_reserved, :check_universal, :check_policy, :check_rbs_type, :check_sensitive,
                         :description_from, :resolve_type, :nested?
  end
end
