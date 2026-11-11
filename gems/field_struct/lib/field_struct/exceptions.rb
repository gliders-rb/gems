# frozen_string_literal: true

module FieldStruct
  # Root of every error FieldStruct raises itself.
  class Error < StandardError; end

  # Raised by a setter under +coercion_policy :raise+.
  class CoercionError < Error
    # @return [Symbol, nil] the field that refused the value
    attr_reader :field_name

    # @return [Exception, nil] the coercion exception
    attr_reader :original

    # @param message [String]
    # @param field_name [Symbol, nil]
    # @param original [Exception, nil]
    def initialize(message = nil, field_name: nil, original: nil)
      @original = original
      @field_name = field_name
      super(message)
    end
  end

  # Raised by a setter on an +immutable!+ instance after construction.
  class ImmutableError < Error; end

  # Raised under +unknown_attributes :raise+.
  class UnknownAttributeError < Error
    # @return [Array<Symbol>] the unknown keys, in input order
    attr_reader :keys

    # @param message [String]
    # @param keys [Array<Symbol>]
    def initialize(message = nil, keys: [])
      @keys = keys
      super(message)
    end
  end
end
