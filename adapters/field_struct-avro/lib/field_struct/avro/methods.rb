# frozen_string_literal: true

module FieldStruct
  module Avro
    # Opt-in: +include FieldStruct::Avro::Methods+ in a struct adds +to_avro_schema+, +to_avro+ and +from_avro+.
    module Methods
      # @param base [::Class]
      # @return [void]
      def self.included(base)
        base.extend(ClassMethods)
      end

      # The class-level methods +Methods+ adds.
      module ClassMethods
        # @param options [::Object] the options of {FieldStruct::Avro.schema}
        # @return [::Hash{::String=>::Object}] see {FieldStruct::Avro.schema}
        def to_avro_schema(**options)
          FieldStruct::Avro.schema(self, **options)
        end

        # @param bytes [::String] Avro binary
        # @param options [::Object] the options of {FieldStruct::Avro.decode}
        # @return [FieldStruct::Base] an instance of the class
        def from_avro(bytes, **options)
          FieldStruct::Avro.decode(self, bytes, **options)
        end
      end

      # @param options [::Object] the options of {FieldStruct::Avro.encode}
      # @return [::String] Avro binary
      def to_avro(**options)
        FieldStruct::Avro.encode(self, **options)
      end
    end
  end
end
