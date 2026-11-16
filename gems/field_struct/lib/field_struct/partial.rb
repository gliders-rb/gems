# frozen_string_literal: true

module FieldStruct
  # INTERNAL. Builds the class +Klass.partial+ returns (FS-B104b): a sibling of +Klass+ with every field optional.
  module PartialBuilder
    # @param source [Class] the +FieldStruct::Base+ subclass to copy
    # @return [Class] the new class, already named +<source>::Partial+
    # @raise [ArgumentError] when +source+ already has its own +Partial+ constant
    def self.call(source)
      label = source.display_name
      if source.const_defined?(:Partial, false)
        raise ArgumentError, "#{label}::Partial is already defined; #{label}.partial would replace it"
      end

      copy = Class.new(Base)
      source.metadata.each do |field|
        loose = loosened(field)
        copy.metadata.add(loose)
        copy.send(:define_accessors, loose)
      end
      source.metadata.serializations.each { |format, mapping| copy.metadata.add_serialization(format, mapping) }
      copy_policies(source, copy)
      source.const_set(:Partial, copy)
    end

    # The same field, optional, not nullable, with no default.
    #
    # @param field [FieldStruct::Field]
    # @return [FieldStruct::Field]
    def self.loosened(field)
      Field.new(name: field.name, type: field.type, type_instance: field.type_instance, required: false, nullable: false,
                default: nil, coercion_policy: field.coercion_policy, description: field.description,
                rbs_type: field.rbs_type, sensitive: field.sensitive?, **field.options)
    end

    # @param source [Class]
    # @param copy [Class]
    # @return [void]
    def self.copy_policies(source, copy)
      copy.coercion_policy(source.coercion_policy)
      copy.unknown_attributes(source.unknown_attributes)
      copy.json_omit(:unset)
      copy.immutable! if source.immutable?
      copy.frozen! if source.frozen_on_construct?
    end

    private_class_method :loosened, :copy_policies
  end
end
