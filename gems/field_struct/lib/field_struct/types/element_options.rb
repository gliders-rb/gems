# frozen_string_literal: true

module FieldStruct
  module Types
    # Declaration-time validation of an array's +element:+ Hash against the element type's own schema.
    module ElementOptions
      # @param element_class [::Class] the element type's class
      # @param element [::Hash, nil] the declared +element:+ options
      # @param registry [FieldStruct::Registry]
      # @param field_name [::Symbol]
      # @return [::Hash, nil] the resolved options, frozen; +nil+ when empty or absent
      # @raise [ArgumentError] with an +in element: of array field :name,+ prefix
      def self.call(element_class, element, registry:, field_name:)
        return nil if element.nil? || element.empty?

        prefix = "in element: of array field #{field_name.inspect}, "
        refuse_composite(element_class, prefix)
        element.each_key { |key| check_key(element_class, key, prefix) }
        resolved = OptionChecker.element(element_class, element, registry: registry, field_name: field_name)
        resolved.freeze
      rescue ::ArgumentError => e
        raise if e.message.start_with?(prefix)

        raise ::ArgumentError, "#{prefix}#{e.message}", cause: nil
      end

      def self.refuse_composite(element_class, prefix)
        return unless element_class <= Types::Array || element_class <= Types::Union

        raise ::ArgumentError, "#{prefix}element options are not supported for #{element_class.short_name} elements"
      end

      def self.check_key(element_class, key, prefix)
        if FieldBuilder::UNIVERSAL_OPTIONS.include?(key)
          raise ::ArgumentError, "#{prefix}#{key}: is a field option, not an element option. Declare it on the field itself."
        end

        schema = element_class.option_schema
        return if schema.key?(key)

        name = element_class.short_name
        article = name.match?(/\A[AEIOU]/) ? 'an' : 'a'
        accepts = schema.empty? ? "#{name} accepts no options." : "#{name} accepts: #{schema.keys.join(', ')}."
        raise ::ArgumentError, "#{prefix}#{key}: is not #{article} #{name} option. #{accepts}"
      end

      private_class_method :refuse_composite, :check_key
    end
  end
end
