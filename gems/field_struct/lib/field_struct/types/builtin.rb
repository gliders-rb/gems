# frozen_string_literal: true

module FieldStruct
  module Types
    # Registers every built-in type under its name.
    #
    # @param registry [FieldStruct::Registry]
    # @return [FieldStruct::Registry] the same registry
    def self.install(registry)
      registry
        .register(:string, String)
        .register(:immutable_string, ImmutableString)
        .register(:integer, Integer)
        .register(:float, Float)
        .register(:big_decimal, BigDecimal)
        .register(:decimal, :big_decimal)
        .register(:boolean, Boolean)
        .register(:date, Date)
        .register(:time, Time)
        .register(:datetime, DateTime)
        .register(:value, Value)
        .register(:array, Array)
        .register(:symbol, Symbol)
        .register(:uuid, UUID)
        .register(:url, URL)
        .register(:email, Email)
        .register(:union, Union)
        .register(:binary, Binary)
    end
  end
end
