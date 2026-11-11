# frozen_string_literal: true

module FieldStruct
  # The class-level configuration macros of {Base}: policies, mutability flags and cross-field validators.
  module ClassMacros
    # Reads or sets what happens when a value cannot be coerced. Inherited; a child's value never changes its parent.
    #
    # @param policy [Symbol, nil] +:keep_raw+, +:replace+ or +:raise+; omit to read
    # @return [Symbol]
    # @raise [ArgumentError] for any other value
    def coercion_policy(policy = nil)
      return inherited_setting(:@coercion_policy, :coercion_policy, :keep_raw) if policy.nil?

      check_policy!(policy, Base::VALID_COERCION_POLICIES, 'coercion policy')
      @coercion_policy = policy
    end

    # Reads or sets what happens to input keys that match no field. Inherited like {.coercion_policy}.
    #
    # @param policy [Symbol, nil] +:ignore+ or +:raise+; omit to read
    # @return [Symbol]
    # @raise [ArgumentError] for any other value
    def unknown_attributes(policy = nil)
      return inherited_setting(:@unknown_attributes, :unknown_attributes, :ignore) if policy.nil?

      check_policy!(policy, Base::VALID_UNKNOWN_POLICIES, 'unknown_attributes policy')
      @unknown_attributes = policy
    end

    # Refuses every setter call after construction (+ImmutableError+). One-way; inherited.
    #
    # @return [true]
    def immutable!
      @immutable = true
    end

    # Freezes instances at the end of +new+. One-way; inherited.
    #
    # @return [true]
    def frozen!
      @frozen_on_construct = true
    end

    # @return [Boolean] whether this class or an ancestor called {.immutable!}
    def immutable?
      flagged?(:@immutable, :immutable?)
    end

    # @return [Boolean] whether this class or an ancestor called {.frozen!}
    def frozen_on_construct?
      flagged?(:@frozen_on_construct, :frozen_on_construct?)
    end

    # Registers cross-field validators: each method name and the block is its own validator.
    #
    # @param method_names [Array<Symbol>] public instance methods called with no arguments
    # @yieldparam record [FieldStruct::Base]
    # @return [self]
    def validate(*method_names, &block)
      method_names.each { |method_name| validators << ->(record) { record.public_send(method_name) } }
      validators << block if block
      self
    end

    # Declares the external names a format uses: internal field name to external name. Last write per format wins;
    # mappings are inherited as a snapshot. Only +:json+ is wired into the gem; other formats are stored for other gems.
    #
    # @param format [Symbol, String] e.g. +:json+
    # @param mapping [Hash{Symbol=>Symbol,String}] internal name to external name
    # @return [self]
    # @raise [ArgumentError] when a key is not a declared field
    def serialize(format, **mapping)
      mapping = mapping.to_h { |internal, external| [internal.to_sym, external.to_s] }
      undeclared = mapping.keys.reject { |name| metadata[name] }
      unless undeclared.empty?
        raise ArgumentError, "serialize #{format.to_sym.inspect} references undeclared field(s): " \
                             "#{undeclared.map(&:inspect).join(', ')}. Declare fields before calling serialize."
      end

      metadata.add_serialization(format, mapping)
      self
    end

    # Builds an instance from a JSON object: parses with Oj (decimals arrive as BigDecimal), maps external names back
    # (nested structs and arrays of them through their own mappings), then calls +new+.
    #
    # @param json [String]
    # @return [FieldStruct::Base]
    # @raise [ArgumentError] when the root is not an object
    # @raise [EncodingError] when the JSON is malformed (the message never quotes the input)
    def from_json(json)
      JsonCodec.load(self, json)
    end

    # @return [Array<Proc>] the validators, inherited as a copy when the subclass was created
    def validators
      @validators ||= []
    end

    private

    def check_policy!(policy, allowed, label)
      return if allowed.include?(policy)

      raise ArgumentError, "unknown #{label} #{policy.inspect} (expected one of #{allowed.inspect})"
    end

    def inherited(subclass)
      super
      subclass.instance_variable_set(:@metadata, Metadata.new.merge(metadata))
      subclass.instance_variable_set(:@validators, validators.dup)
    end

    def inherited_setting(ivar, reader, default)
      value = instance_variable_get(ivar)
      return value if value

      superclass.respond_to?(reader) ? superclass.public_send(reader) : default
    end

    def flagged?(ivar, reader)
      return true if instance_variable_get(ivar)

      superclass.respond_to?(reader) ? superclass.public_send(reader) : false
    end
  end
end
