# frozen_string_literal: true

module FieldStruct
  # Namespace for the built-in types and the type contract.
  module Types
    # The type contract. A custom type subclasses this, implements {#coerce} and {#ruby_type},
    # and may override {#missing?}, +own_option_schema+ and +resolve_options+.
    class Base
      class << self
        # The options this class itself declares. Override in a subclass.
        #
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}] option name to descriptor (see {.option})
        def own_option_schema
          {}
        end

        # The superclass schema merged with {.own_option_schema}; own entries win,
        # inherited keys keep their position.
        #
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}] frozen and memoized per class
        def option_schema
          @option_schema ||= begin
            inherited = superclass.respond_to?(:option_schema) ? superclass.option_schema : {}
            inherited.merge(own_option_schema).freeze
          end
        end

        # Builds an option descriptor.
        #
        # @param type [::Class, ::Array<::Class>] the classes a value may be an instance of
        # @param required [Boolean]
        # @param presets [::Array<::Symbol>] preset names the option accepts
        # @return [::Hash{::Symbol=>::Object}] frozen +{type:, required:, presets:}+
        def option(type:, required: false, presets: [])
          { type: [type].flatten.freeze, required: required, presets: presets.dup.freeze }.freeze
        end

        # Declaration-time hook: turn preset Symbols into values and reject bad ones. A type may also declare
        # +registry:+ and +field_name:+ keywords to receive the field's registry chain and name.
        #
        # @param options [::Hash{::Symbol=>::Object}]
        # @return [::Hash{::Symbol=>::Object}]
        def resolve_options(options, **)
          options
        end

        # Builds the instance a Field uses, from the resolved options.
        #
        # @param options [::Hash{::Symbol=>::Object}] the options after {.resolve_options} and the +format:+ prefill
        # @return [::Array(FieldStruct::Types::Base, ::Hash)] the instance and the options to store on the Field
        def instantiate(options)
          [new, options]
        end

        # @param key [::Symbol] a schema option marked +required: true+ that a field left out
        # @return [::String] the declaration error message
        def required_option_message(key)
          "#{key}: is required for #{short_name} fields"
        end

        # Resolves a +format:+ value for types without presets.
        #
        # @param format [::String, nil]
        # @return [::String, nil]
        # @raise [ArgumentError] for anything but nil or a String
        def resolve_format(format)
          return format if format.nil? || format.is_a?(::String)

          raise ::ArgumentError, "#{short_name} has no format presets; got #{format.inspect}"
        end

        # @return [::String] the last segment of the class name, or +AnonymousType+
        def short_name
          name ? name.split('::').last : 'AnonymousType'
        end
      end

      # Coerces a value; +nil+ must give +nil+. A failure raises ArgumentError, TypeError or RangeError.
      # Implementations declare the options they consume as keywords and end with a +**+ catch-all.
      #
      # @param _value [::Object]
      # @return [::Object]
      # @raise [NotImplementedError] unless overridden
      def coerce(_value, **)
        raise NotImplementedError, "#{self.class} must implement #coerce"
      end

      # @param value [::Object] an already coerced value
      # @return [Boolean] whether a required field must reject it
      def missing?(value)
        value.nil?
      end

      # @return [::Class, ::Array<::Class>] the Ruby class(es) of coerced values
      # @raise [NotImplementedError] unless overridden
      def ruby_type
        raise NotImplementedError, "#{self.class} must implement #ruby_type"
      end

      # @return [::String, nil] an RBS type to use instead of the derived one
      def rbs_type
        nil
      end

      # @return [::String]
      def inspect
        name = self.class.name
        name = name ? name.sub(/\AFieldStruct/, FieldStruct.inspect_namespace) : 'AnonymousType'
        "#<#{name}>"
      end

      # @param printer [PP]
      # @return [void]
      def pretty_print(printer)
        printer.text(inspect)
      end

      private

      # "a Float" / "an Integer": the input's class with its article. Only ever names the class.
      def class_phrase(value)
        name = value.class.to_s
        "#{name.match?(/\A[AEIOU]/) ? 'an' : 'a'} #{name}"
      end
    end
  end
end
