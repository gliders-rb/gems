# frozen_string_literal: true

module Actionable
  # ActiveModel validation rules over another object: subclass, declare +validates+, build with +Rules.new(delegate)+.
  class ProxyValidator
    include ::ActiveModel::Validations

    # @return [Object] the object whose attributes the rules read
    attr_reader :delegate

    class << self
      # @return [::ActiveModel::Name] built from the class name, +ProxyValidator+ for an anonymous class
      def model_name
        ::ActiveModel::Name.new(self, nil, name || 'ProxyValidator')
      end
    end

    # @param delegate [Object]
    def initialize(delegate)
      @delegate = delegate
    end

    # @return [Hash{Symbol => Array<String>}] +errors.to_hash+ after running the validations
    def formatted_errors
      valid?
      errors.to_hash
    end

    # Attribute reads go to the delegate when it responds to them.
    #
    # @param name [Symbol]
    # @return [Object]
    def method_missing(name, ...)
      delegate.respond_to?(name) ? delegate.public_send(name, ...) : super
    end

    # @param name [Symbol]
    # @param include_private [Boolean]
    # @return [Boolean]
    def respond_to_missing?(name, include_private = false)
      delegate.respond_to?(name) || super
    end
  end
end
