# frozen_string_literal: true

module FieldStruct
  # Declaration-time option checks (steps 3 to 7 of the declaration order): wrong-type keys, required options,
  # shapes, the type's own +resolve_options+ and the +format:+ prefill. Raises ArgumentError at the first failure.
  module OptionChecker
    # @param type_class [Class] the field's type class
    # @param options [Hash{Symbol=>Object}] every non-universal option, as declared
    # @param registry [FieldStruct::Registry] the registry chain the field's type was resolved through
    # @param field_name [Symbol]
    # @return [Hash{Symbol=>Object}] the options to store: presets resolved, +format:+ prefilled
    def self.call(type_class, options, registry:, field_name:)
      check_keys(type_class, options, registry)
      check_required(type_class, options)
      check_shapes(type_class, options)
      resolved = resolve(type_class, options, registry, field_name)
      prefill_format(type_class, resolved)
    end

    # The checks an array's +element:+ options get: shapes, then the element type's +resolve_options+.
    # (Keys are checked by the caller, which words the errors for elements.)
    #
    # @param type_class [Class] the element type's class
    # @param options [Hash{Symbol=>Object}]
    # @param registry [FieldStruct::Registry]
    # @param field_name [Symbol]
    # @return [Hash{Symbol=>Object}]
    def self.element(type_class, options, registry:, field_name:)
      check_shapes(type_class, options)
      resolve(type_class, options, registry, field_name)
    end

    # Short class name used in messages ("Float", "ImmutableString").
    #
    # @param klass [Class]
    # @return [String]
    def self.short(klass)
      klass.name ? klass.name.split('::').last : klass.to_s
    end

    def self.check_keys(type_class, options, registry)
      schema = type_class.option_schema
      options.each_key do |key|
        next if schema.key?(key)

        owners = registry.type_classes.select { |candidate| candidate.option_schema.key?(key) }
        next if owners.empty?

        raise ::ArgumentError, "#{key}: option does not apply to #{type_class.short_name} fields. " \
                               "It applies to: #{owners.map(&:short_name).join(', ')}."
      end
    end

    def self.check_required(type_class, options)
      type_class.option_schema.each do |key, descriptor|
        raise ::ArgumentError, type_class.required_option_message(key) if descriptor[:required] && options[key].nil?
      end
    end

    def self.check_shapes(type_class, options)
      type_class.option_schema.each do |key, descriptor|
        value = options[key]
        next if value.nil? || descriptor[:type].any? { |klass| value.is_a?(klass) }

        expected = descriptor[:type].map { |klass| short(klass) }.join(' or ')
        raise ::ArgumentError,
              "#{key}: on #{type_class.short_name} expects #{expected}, got #{value.class} (#{value.inspect})"
      end
    end

    # Calls the type's hook, passing +registry:+ and +field_name:+ only if it declares them (4.9.1 says
    # +resolve_options(options)+, and a custom type may keep that signature).
    def self.resolve(type_class, options, registry, field_name)
      accepted = type_class.method(:resolve_options).parameters
      extras = { registry: registry, field_name: field_name }.select do |name, _|
        accepted.any? { |kind, param| kind == :keyrest || (kind == :key && param == name) || (kind == :keyreq && param == name) }
      end
      type_class.resolve_options(options, **extras)
    end

    def self.prefill_format(type_class, options)
      return options unless type_class.respond_to?(:default_format) && !options.key?(:format)

      options.merge(format: type_class.default_format)
    end

    private_class_method :check_keys, :check_required, :check_shapes, :resolve, :prefill_format
  end
end
