# frozen_string_literal: true

require 'date'
require 'time'
require 'pathname'
require 'pp'
require 'bigdecimal'
require 'oj'

require_relative 'field_struct/version'
require_relative 'field_struct/exceptions'
require_relative 'field_struct/errors'
require_relative 'field_struct/registry'
require_relative 'field_struct/types/base'
require_relative 'field_struct/types/preset_resolver'
require_relative 'field_struct/types/string'
require_relative 'field_struct/types/immutable_string'
require_relative 'field_struct/types/integer'
require_relative 'field_struct/types/float'
require_relative 'field_struct/types/big_decimal'
require_relative 'field_struct/types/boolean'
require_relative 'field_struct/types/rfc3339_format'
require_relative 'field_struct/types/zone'
require_relative 'field_struct/types/temporal'
require_relative 'field_struct/types/date'
require_relative 'field_struct/types/time'
require_relative 'field_struct/types/datetime'
require_relative 'field_struct/types/symbol'
require_relative 'field_struct/types/format_presets'
require_relative 'field_struct/types/uuid'
require_relative 'field_struct/types/url'
require_relative 'field_struct/types/email'
require_relative 'field_struct/types/binary'
require_relative 'field_struct/types/value'
require_relative 'field_struct/types/nested'
require_relative 'field_struct/types/element_options'
require_relative 'field_struct/types/array'
require_relative 'field_struct/types/union'
require_relative 'field_struct/types/builtin'
require_relative 'field_struct/restrictions'
require_relative 'field_struct/describer'
require_relative 'field_struct/field'
require_relative 'field_struct/option_checker'
require_relative 'field_struct/metadata'
require_relative 'field_struct/model_name'
require_relative 'field_struct/field_builder'
require_relative 'field_struct/class_macros'
require_relative 'field_struct/json_codec'
require_relative 'field_struct/base'
require_relative 'field_struct/scaffold'
require_relative 'field_struct/introspection'
require_relative 'field_struct/rbs'

# Typed plain Ruby objects with declared, coerced, validated fields.
module FieldStruct
  # Placeholder printed by +inspect+ in place of sensitive values.
  # @return [::String]
  FILTERED = '[FILTERED]'

  class << self
    # The directory that contains +lib/+.
    #
    # @return [Pathname]
    def root
      @root ||= Pathname.new(__dir__).parent
    end

    # The memoized base registry, seeded with every built-in type.
    #
    # @return [FieldStruct::Registry]
    def types
      @types ||= Types.install(Registry.new)
    end

    # Builds a registry, evaluating the block with the new registry as +self+.
    #
    # @param parent [FieldStruct::Registry, nil] where unknown names fall through to
    # @yield evaluated with the registry as +self+
    # @return [FieldStruct::Registry]
    def new_registry(parent = types, &block)
      registry = Registry.new(parent)
      registry.instance_eval(&block) if block
      registry
    end

    # Defines a top-level constant for FieldStruct and switches every +inspect+ prefix to it.
    #
    # @param name [Symbol, String] the constant name
    # @return [Module] FieldStruct
    # @raise [NameError] when the constant already names something else
    def use_alias!(name = :FS)
      name = name.to_sym
      if Object.const_defined?(name, false)
        existing = Object.const_get(name, false)
        raise NameError, "::#{name} is already defined (#{existing.inspect}); not aliasing FieldStruct" unless existing.equal?(self)
      else
        Object.const_set(name, self)
      end
      @inspect_namespace = name.to_s
      self
    end

    # The prefix library +inspect+ output uses.
    #
    # @return [String] +'FieldStruct'+ or the alias name
    def inspect_namespace
      @inspect_namespace || 'FieldStruct'
    end
  end
end
