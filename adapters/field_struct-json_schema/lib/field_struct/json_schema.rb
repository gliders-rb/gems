# frozen_string_literal: true

require 'field_struct'

unless defined?(FieldStruct::Introspection)
  raise LoadError, 'field_struct-json_schema needs FieldStruct::Introspection, which field_struct >= 1.0.0.pre1 provides; ' \
                   'upgrade field_struct'
end

require_relative 'json_schema/version'
require_relative 'json_schema/pattern'
require_relative 'json_schema/override'
require_relative 'json_schema/nullable'
require_relative 'json_schema/defaults'
require_relative 'json_schema/scalar'
require_relative 'json_schema/builder'
require_relative 'json_schema/copy'
require_relative 'json_schema/stamp'
require_relative 'json_schema/cache'

# The field_struct namespace; this gem adds {JSONSchema}.
module FieldStruct
  # Generates the JSON Schema (draft 2020-12) of the JSON a FieldStruct class writes with +to_json+.
  module JSONSchema
    # @return [::Hash{::String=>::Object}] the one blank a +:binary+ field counts as missing
    EMPTY_STRING = { 'type' => 'string', 'maxLength' => 0 }.freeze
    # @return [::Hash{::String=>::String}] text that +String#strip+ would reduce to nothing
    BLANK_STRING = { 'type' => 'string', 'pattern' => '^[\x00\t\n\v\f\r ]*$' }.freeze
    # @return [::String] the form +to_json+ gives a BigDecimal
    DECIMAL_PATTERN = '^-?[0-9]+\.[0-9]+$'
    # @return [::String] the dialect named by every generated document
    DRAFT = 'https://json-schema.org/draft/2020-12/schema'

    # Opt-in: adds +to_json_schema+ to a struct class.
    module Methods
      # @param base [::Class]
      # @return [void]
      def self.included(base)
        base.extend(ClassMethods)
      end

      # The class-level method +Methods+ adds.
      module ClassMethods
        # @param serialization [::Symbol, ::String] the serialization whose names the schema uses
        # @return [::Hash{::String=>::Object}] see {FieldStruct::JSONSchema.generate}
        def to_json_schema(serialization: :json)
          FieldStruct::JSONSchema.generate(self, serialization: serialization)
        end
      end
    end

    CACHE = Cache.new
    private_constant :CACHE

    class << self
      # The JSON Schema of the JSON +klass+ writes with +to_json+.
      #
      # @param klass [::Class<FieldStruct::Base>] a +FieldStruct::Base+ subclass
      # @param serialization [::Symbol, ::String] the serialization whose +serialize+ names the properties use
      # @return [::Hash{::String=>::Object}] a fresh deep copy; mutating it changes nothing else
      # @raise [::ArgumentError] on a bad argument, a bad override or a failing hook
      def generate(klass, serialization: :json)
        unless klass.is_a?(::Class) && klass < FieldStruct::Base
          raise ::ArgumentError, "FieldStruct::JSONSchema.generate expects a FieldStruct::Base subclass, got #{klass.inspect}"
        end

        serialization = serialization.to_sym if serialization.is_a?(::String)
        unless serialization.is_a?(::Symbol)
          raise ::ArgumentError, "FieldStruct::JSONSchema.generate expects serialization: to be a Symbol, got #{serialization.inspect}"
        end

        CACHE.fetch(klass, serialization)
      end

      # An ECMA-262 pattern matching exactly the strings +regexp+ matches (under the +u+ flag), or nil.
      #
      # @param regexp [::Regexp]
      # @return [::String, nil] nil when no exact, safe equivalent exists
      def pattern_for(regexp)
        raise ::ArgumentError, "FieldStruct::JSONSchema.pattern_for expects a Regexp, got #{regexp.inspect}" unless regexp.is_a?(::Regexp)

        Pattern.translate(regexp)
      end

      # Empties the schema cache (it holds classes alive: call it on code reload).
      #
      # @return [nil]
      def clear_cache
        CACHE.clear
        nil
      end
    end
  end
end
