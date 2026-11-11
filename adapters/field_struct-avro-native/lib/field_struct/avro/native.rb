# frozen_string_literal: true

require 'bigdecimal'
require 'date'
require 'field_struct/avro'
require_relative 'native/version'
require_relative 'native/compiler'

# A precompiled platform gem keeps one binary per Ruby minor version in a folder named for it; a source build
# (and `rake compile`) puts the single binary next to this file.
begin
  require_relative "#{RUBY_VERSION[/\A\d+\.\d+/]}/field_struct_avro_native"
rescue LoadError
  require_relative 'field_struct_avro_native'
end

# The field_struct namespace.
module FieldStruct
  # Apache Avro for field_struct classes.
  module Avro
    # An optional Rust encoder behind +FieldStruct::Avro.encode+. Requiring this file swaps the binary write: the
    # datum +to_datum+ built is written by an encoding plan compiled once per parsed writer schema. A datum the plan is
    # not sure about (a value of an unexpected class, out of range, needing rounding) is written by the pure-Ruby path
    # instead, so the bytes and every error stay what the pure path gives.
    module Native
      # The instance variable a parsed schema keeps its compiled plan in, so the plan lives and dies with the
      # schema the adapter's cache holds (a rebuilt or cleared entry gets a new schema and a new plan).
      PLAN_IVAR = :@field_struct_avro_native_plan
      private_constant :PLAN_IVAR

      class << self
        # @return [Boolean] whether +FieldStruct::Avro.encode+ goes through the native encoder
        def enabled?
          FieldStruct::Avro.singleton_class.ancestors.include?(Write)
        end

        # The Avro binary of a datum, or nil when the native encoder leaves it to the pure path.
        #
        # @param schema [::Object] a parsed +Avro::Schema+
        # @param datum [::Object] what +FieldStruct::Avro.to_datum+ returns for that schema
        # @return [::String, nil] binary bytes, or nil
        def encode(schema, datum)
          plan = plan_for(schema)
          plan&.encode(datum)
        end

        private

        def plan_for(schema)
          plan = schema.instance_variable_get(PLAN_IVAR)
          return plan || nil unless plan.nil?

          plan = compile(schema)
          schema.instance_variable_set(PLAN_IVAR, plan || false) unless schema.frozen?
          plan
        end

        def compile(schema)
          nodes, root = Compiler.call(schema)
          nodes && Plan.new(nodes, root)
        end
      end

      # Prepended to +FieldStruct::Avro+'s singleton class: the binary write tries the plan first.
      module Write
        private

        def write(parsed, datum, struct)
          Native.encode(parsed, datum) || super
        end
      end

      FieldStruct::Avro.singleton_class.prepend(Write)
    end
  end
end
