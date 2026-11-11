# frozen_string_literal: true

module Actionable
  # Process-wide map from action class name to class. Not synchronized; nothing removes entries.
  class Registry
    include Enumerable

    def initialize
      @classes = {}
    end

    # Registers a named class, replacing any class already under that name. Anonymous classes are ignored.
    #
    # @param klass [Class]
    # @return [self]
    def register(klass)
      @classes[klass.name] = klass if klass.name
      self
    end

    # @param name [String, Symbol]
    # @return [Class, nil]
    def [](name)
      @classes[name.to_s]
    end

    # @yieldparam name [String]
    # @yieldparam klass [Class]
    # @return [Enumerator<Array(String, Class)>, self]
    def each(&block)
      return enum_for(:each) unless block

      @classes.each(&block)
      self
    end

    # @return [Array<String>]
    def keys = @classes.keys

    # @return [Array<Class>]
    def values = @classes.values

    # @return [Integer]
    def size = @classes.size

    # @return [Boolean]
    def empty? = @classes.empty?
  end
end
