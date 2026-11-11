# frozen_string_literal: true

module FieldStruct
  # Maps type names (Symbols) to type classes, with an optional parent to fall back to.
  class Registry
    # @return [FieldStruct::Registry, nil]
    attr_reader :parent

    # @param parent [FieldStruct::Registry, nil]
    def initialize(parent = nil)
      @parent = parent
      @entries = {}
    end

    # Registers a type class, or an alias to an already registered name.
    # An alias is resolved now, so re-registering its target later does not move it.
    #
    # @param name [Symbol, String]
    # @param target [Class, Symbol, String] a type class, or the name to alias
    # @return [self]
    # @raise [KeyError] when an alias target is unknown
    def register(name, target)
      @entries[name.to_sym] = target.is_a?(Class) ? target : lookup(target)
      self
    end

    # @param name [Symbol, String]
    # @return [Class]
    # @raise [KeyError] when no registry in the chain knows the name
    def lookup(name)
      key = name.to_sym
      return @entries[key] if @entries.key?(key)
      return @parent.lookup(key) if @parent&.key?(key)

      raise KeyError, "no FieldStruct type registered for #{key.inspect}"
    end

    # @param name [Symbol, String]
    # @return [Boolean] whether this registry or an ancestor knows the name
    def key?(name)
      key = name.to_sym
      @entries.key?(key) || (@parent ? @parent.key?(key) : false)
    end

    # @return [Array<Class>] distinct classes resolvable here: own first, then the parent's
    def type_classes
      (@entries.values + (@parent ? @parent.type_classes : [])).uniq
    end

    # @return [String]
    def inspect
      "#<#{FieldStruct.inspect_namespace}::Registry types=#{@entries.keys.inspect}#{' parent' if @parent}>"
    end
  end
end
